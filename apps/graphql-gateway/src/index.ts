import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import { createSchema, createYoga } from 'graphql-yoga';
import { GraphQLError } from 'graphql';
import { GetCommand, PutCommand, QueryCommand, ScanCommand, TransactWriteCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { DomainError, FlagNames, type DomainErrorShape, type Environment, type FeatureFlags, type SagaEvent, type SagaState, type SagaTransaction, defaultFlags, dynamoDocumentClient, isValidSagaTransition, nowIso, parseEnvironment, tableName } from '@aegisvolt/contracts';
import { Metrics, log } from '@aegisvolt/shared-observability';

const environment = parseEnvironment();
const sagaTable = tableName('saga', environment);
const flagsTable = tableName('flags', environment);
const db = dynamoDocumentClient();
const metrics = new Metrics();
const urls = {
  station: process.env.STATION_SERVICE_URL ?? 'http://localhost:3001',
  billing: process.env.BILLING_SERVICE_URL ?? 'http://localhost:3002',
  dispatch: process.env.DISPATCH_SERVICE_URL ?? 'http://localhost:3003'
};

type SagaItem = SagaTransaction & { PK: string; SK: string; GSI1PK: string; GSI1SK: string; compensationPlan?: Array<'REFUND' | 'RELEASE'>; compensationCompleted?: Array<'REFUND' | 'RELEASE'> };
type FlagItem = { PK: string; SK: string; name: string; value: boolean; environment: Environment; updatedAt: string; updatedBy: string };
const sagaKey = (sagaId: string) => ({ PK: `SAGA#${sagaId}`, SK: 'META' });
const idempotencyKey = (key: string) => ({ PK: `IDEMPOTENCY#${key}`, SK: 'META' });
const flagKey = (name: string) => ({ PK: `FLAG#${name}`, SK: 'CURRENT' });

class DependencyClient {
  private failures = 0;
  private openUntil = 0;
  private inFlight = 0;
  constructor(private readonly dependency: string, private readonly baseUrl: string, private readonly maxInFlight = 8) {}
  async request<T>(path: string, options: { method?: string; body?: unknown; correlationId?: string; safeRetry?: boolean } = {}): Promise<T> {
    if (Date.now() < this.openUntil) throw new DomainError('DEPENDENCY_CIRCUIT_OPEN', `${this.dependency} está temporalmente aislado.`, true);
    if (this.inFlight >= this.maxInFlight) throw new DomainError('DEPENDENCY_BULKHEAD_REJECTED', `${this.dependency} alcanzó su límite de concurrencia.`, true);
    this.inFlight += 1;
    const attempts = options.safeRetry === false ? 1 : 3;
    try {
      let lastError: unknown;
      for (let attempt = 0; attempt < attempts; attempt += 1) {
        const controller = new AbortController(); const timeout = setTimeout(() => controller.abort(), 2_000);
        try {
          const response = await fetch(`${this.baseUrl}${path}`, {
            method: options.method ?? 'GET', signal: controller.signal,
            headers: { 'content-type': 'application/json', 'x-correlation-id': options.correlationId ?? randomUUID() },
            body: options.body === undefined ? undefined : JSON.stringify(options.body)
          });
          const payload = await response.json() as T & { code?: string; message?: string; retryable?: boolean };
          if (response.ok) { this.failures = 0; return payload; }
          const retryable = response.status >= 500 || payload.retryable === true;
          const error = new DomainError(payload.code ?? 'DEPENDENCY_ERROR', payload.message ?? `${this.dependency} falló.`, retryable);
          if (!retryable || attempt === attempts - 1) throw error;
          lastError = error;
        } catch (error) {
          lastError = error;
          if (error instanceof DomainError && !error.retryable) throw error;
          if (attempt === attempts - 1) throw new DomainError('DEPENDENCY_TIMEOUT', `${this.dependency} excedió el tiempo de respuesta.`, true);
        } finally { clearTimeout(timeout); }
        await new Promise((resolve) => setTimeout(resolve, 100 * (2 ** attempt) + Math.floor(Math.random() * 80)));
      }
      throw lastError;
    } catch (error) {
      this.failures += 1;
      if (this.failures >= 3) this.openUntil = Date.now() + 5_000;
      throw error;
    } finally { this.inFlight -= 1; }
  }
}
const stationClient = new DependencyClient('station-reservation-service', urls.station);
const billingClient = new DependencyClient('billing-wallet-service', urls.billing);
const dispatchClient = new DependencyClient('energy-dispatch-service', urls.dispatch);

const toError = (error: unknown): DomainErrorShape => {
  if (error instanceof DomainError) return { code: error.code, message: error.message, retryable: error.retryable, details: error.details };
  return { code: 'SAGA_UNEXPECTED_ERROR', message: 'Fallo no esperado; la transacción queda disponible para reconciliación.', retryable: true };
};
const getSaga = async (sagaId: string): Promise<SagaItem | undefined> => (await db.send(new GetCommand({ TableName: sagaTable, Key: sagaKey(sagaId), ConsistentRead: true }))).Item as SagaItem | undefined;
const getSagaByIdempotency = async (idempotencyKey: string): Promise<SagaItem | undefined> => {
  const marker = await db.send(new GetCommand({ TableName: sagaTable, Key: { PK: `IDEMPOTENCY#${idempotencyKey}`, SK: 'META' }, ConsistentRead: true }));
  if (marker.Item?.sagaId) return getSaga(marker.Item.sagaId as string);
  const result = await db.send(new QueryCommand({ TableName: sagaTable, IndexName: 'GSI1', KeyConditionExpression: 'GSI1PK = :pk', ExpressionAttributeValues: { ':pk': `IDEMPOTENCY#${idempotencyKey}` }, Limit: 1 }));
  return result.Items?.[0] as SagaItem | undefined;
};
const record = async (sagaId: string, state: SagaState, event: Omit<SagaEvent, 'at'>, error?: DomainErrorShape, updates: Partial<Pick<SagaItem, 'sessionId' | 'compensationPlan' | 'compensationCompleted'>> = {}): Promise<SagaItem> => {
  const current = await getSaga(sagaId);
  if (!current) throw new DomainError('SAGA_NOT_FOUND', 'La SAGA no existe.');
  if (!isValidSagaTransition(current.state, state)) throw new DomainError('INVALID_SAGA_TRANSITION', `Transición no permitida: ${current.state} -> ${state}.`);
  const fullEvent: SagaEvent = { at: nowIso(), ...event };
  const expressionValues: Record<string, unknown> = { ':state': state, ':updatedAt': nowIso(), ':empty': [], ':event': [fullEvent] };
  const setClauses = ['#state = :state', 'updatedAt = :updatedAt', 'events = list_append(if_not_exists(events, :empty), :event)'];
  const names: Record<string, string> = { '#state': 'state' };
  if (error) { setClauses.push('#error = :error'); names['#error'] = 'error'; expressionValues[':error'] = error; }
  for (const [name, value] of Object.entries(updates)) { if (value !== undefined) { setClauses.push(`${name} = :${name}`); expressionValues[`:${name}`] = value; } }
  await db.send(new UpdateCommand({ TableName: sagaTable, Key: sagaKey(sagaId), UpdateExpression: `SET ${setClauses.join(', ')}`, ExpressionAttributeNames: names, ExpressionAttributeValues: expressionValues }));
  return (await getSaga(sagaId))!;
};
const createSaga = async (input: { fleetId: string; stationId: string; connectorId: string; idempotencyKey: string; correlationId: string; estimatedCostCents: number }): Promise<SagaItem> => {
  const sagaId = randomUUID(); const createdAt = nowIso();
  const saga: SagaItem = { ...sagaKey(sagaId), GSI1PK: `IDEMPOTENCY#${input.idempotencyKey}`, GSI1SK: `SAGA#${sagaId}`, sagaId, correlationId: input.correlationId, idempotencyKey: input.idempotencyKey, environment, fleetId: input.fleetId, stationId: input.stationId, connectorId: input.connectorId, estimatedCostCents: input.estimatedCostCents, state: 'PENDING', events: [{ at: createdAt, type: 'SAGA_CREATED', status: 'SUCCEEDED' }], createdAt, updatedAt: createdAt };
  try {
    await db.send(new TransactWriteCommand({ TransactItems: [
      { Put: { TableName: sagaTable, Item: { ...idempotencyKey(input.idempotencyKey), sagaId, createdAt }, ConditionExpression: 'attribute_not_exists(PK)' } },
      { Put: { TableName: sagaTable, Item: saga, ConditionExpression: 'attribute_not_exists(PK)' } }
    ] }));
    return saga;
  } catch (error: unknown) {
    if ((error as { name?: string }).name === 'TransactionCanceledException') {
      const existing = await getSagaByIdempotency(input.idempotencyKey);
      if (existing) return existing;
    }
    throw error;
  }
};

let flagsCache: { until: number; value: FeatureFlags } | undefined;
const getFlags = async (): Promise<FeatureFlags> => {
  if (flagsCache && flagsCache.until > Date.now()) return flagsCache.value;
  const defaults = defaultFlags(environment);
  for (const name of FlagNames) {
    try { await db.send(new PutCommand({ TableName: flagsTable, Item: { ...flagKey(name), name, value: defaults[name], environment, updatedAt: nowIso(), updatedBy: 'bootstrap' } satisfies FlagItem, ConditionExpression: 'attribute_not_exists(PK)' })); }
    catch (error: unknown) { if ((error as { name?: string }).name !== 'ConditionalCheckFailedException') throw error; }
  }
  const response = await db.send(new ScanCommand({ TableName: flagsTable }));
  const flags = { ...defaults };
  for (const item of response.Items as FlagItem[] ?? []) if (FlagNames.includes(item.name as typeof FlagNames[number])) flags[item.name as typeof FlagNames[number]] = item.value;
  flagsCache = { until: Date.now() + 5_000, value: flags }; return flags;
};
const updateFlag = async (name: string, value: boolean, actor: string): Promise<FlagItem> => {
  if (!FlagNames.includes(name as typeof FlagNames[number])) throw new DomainError('UNKNOWN_FLAG', 'Flag no reconocida.');
  if (environment === 'prod' && actor !== 'platform-admin') throw new DomainError('FORBIDDEN_FLAG_CHANGE', 'En producción solo platform-admin puede cambiar flags.');
  await db.send(new UpdateCommand({ TableName: flagsTable, Key: flagKey(name), UpdateExpression: 'SET #value = :value, updatedAt = :updatedAt, updatedBy = :actor, environment = :environment, #name = :name', ExpressionAttributeNames: { '#value': 'value', '#name': 'name' }, ExpressionAttributeValues: { ':value': value, ':updatedAt': nowIso(), ':actor': actor, ':environment': environment, ':name': name } }));
  flagsCache = undefined; return (await db.send(new GetCommand({ TableName: flagsTable, Key: flagKey(name) }))).Item as FlagItem;
};

const release = async (saga: SagaItem): Promise<void> => { await stationClient.request(`/reservations/${saga.connectorId}/release`, { method: 'POST', correlationId: saga.correlationId, body: { sagaId: saga.sagaId, correlationId: saga.correlationId } }); };
const refund = async (saga: SagaItem): Promise<void> => { await billingClient.request('/refunds', { method: 'POST', correlationId: saga.correlationId, body: { sagaId: saga.sagaId, correlationId: saga.correlationId, idempotencyKey: saga.idempotencyKey, environment, fleetId: saga.fleetId, amountCents: saga.estimatedCostCents, reason: 'Compensación por activación no completada' } }); };
const compensate = async (initial: SagaItem, plan: Array<'REFUND' | 'RELEASE'>, cause: DomainErrorShape): Promise<SagaItem> => {
  let saga = await record(initial.sagaId, 'COMPENSATING', { type: 'COMPENSATION_STARTED', status: 'STARTED', detail: plan.join('->') }, cause, { compensationPlan: plan, compensationCompleted: initial.compensationCompleted ?? [] });
  const completed = new Set(saga.compensationCompleted ?? []);
  try {
    for (const step of plan) {
      if (completed.has(step)) continue;
      saga = await record(saga.sagaId, 'COMPENSATING', { type: `${step}_STARTED`, status: 'STARTED' });
      if (step === 'REFUND') await refund(saga); else await release(saga);
      completed.add(step);
      saga = await record(saga.sagaId, 'COMPENSATING', { type: `${step}_SUCCEEDED`, status: 'SUCCEEDED' }, undefined, { compensationCompleted: [...completed] });
    }
    metrics.increment('saga_compensated_total');
    return record(saga.sagaId, 'COMPENSATED', { type: 'COMPENSATION_COMPLETED', status: 'SUCCEEDED' }, cause, { compensationPlan: plan, compensationCompleted: [...completed] });
  } catch (error) {
    const compensationError = toError(error); metrics.increment('saga_compensation_failed_total');
    return record(saga.sagaId, 'COMPENSATION_FAILED', { type: 'COMPENSATION_FAILED', status: 'FAILED', detail: compensationError.code }, compensationError, { compensationPlan: plan, compensationCompleted: [...completed] });
  }
};

const executeSaga = async (original: SagaItem, flags: FeatureFlags): Promise<SagaItem> => {
  let saga = original;
  if (['COMPLETED', 'COMPENSATED'].includes(saga.state)) return saga;
  if (['COMPENSATING', 'COMPENSATION_FAILED'].includes(saga.state)) return compensate(saga, saga.compensationPlan ?? ['REFUND', 'RELEASE'], saga.error ?? { code: 'RECOVERY', message: 'Reconciliación de compensación.', retryable: true });
  try {
    if (saga.state === 'PENDING') {
      saga = await record(saga.sagaId, 'PENDING', { type: 'RESERVE_STARTED', status: 'STARTED' });
      await stationClient.request('/reservations', { method: 'POST', correlationId: saga.correlationId, body: { sagaId: saga.sagaId, correlationId: saga.correlationId, idempotencyKey: saga.idempotencyKey, environment, fleetId: saga.fleetId, stationId: saga.stationId, connectorId: saga.connectorId, requiresFastCharge: flags.ENABLE_FAST_CHARGE_BOOST, expiresInSeconds: 300 } });
      saga = await record(saga.sagaId, 'RESERVED', { type: 'RESERVE_SUCCEEDED', status: 'SUCCEEDED' });
    }
    if (saga.state === 'RESERVED') {
      saga = await record(saga.sagaId, 'RESERVED', { type: 'DEBIT_STARTED', status: 'STARTED' });
      try {
        await billingClient.request('/debits', { method: 'POST', correlationId: saga.correlationId, body: { sagaId: saga.sagaId, correlationId: saga.correlationId, idempotencyKey: saga.idempotencyKey, environment, fleetId: saga.fleetId, amountCents: saga.estimatedCostCents, reason: 'Autorización estimada de carga' } });
      } catch (error) { return compensate(saga, ['RELEASE'], toError(error)); }
      saga = await record(saga.sagaId, 'CHARGED', { type: 'DEBIT_SUCCEEDED', status: 'SUCCEEDED' });
    }
    if (saga.state === 'CHARGED' || saga.state === 'ACTIVATING') {
      if (saga.state === 'CHARGED') saga = await record(saga.sagaId, 'ACTIVATING', { type: 'ACTIVATE_STARTED', status: 'STARTED' });
      try {
        const result = await dispatchClient.request<{ session: { sessionId: string } }>('/activate', { method: 'POST', correlationId: saga.correlationId, body: { sagaId: saga.sagaId, correlationId: saga.correlationId, idempotencyKey: saga.idempotencyKey, environment, fleetId: saga.fleetId, stationId: saga.stationId, connectorId: saga.connectorId, simulateHardwareFault: flags.SIMULATE_CHARGER_HARDWARE_FAULT } });
        saga = await record(saga.sagaId, 'ACTIVATING', { type: 'ACTIVATE_SUCCEEDED', status: 'SUCCEEDED' }, undefined, { sessionId: result.session.sessionId });
        await stationClient.request(`/reservations/${saga.connectorId}/activate`, { method: 'POST', correlationId: saga.correlationId, body: { sagaId: saga.sagaId, sessionId: result.session.sessionId } });
        saga = await record(saga.sagaId, 'COMPLETED', { type: 'CONNECTOR_CHARGING_SUCCEEDED', status: 'SUCCEEDED' }, undefined, { sessionId: result.session.sessionId });
        metrics.increment('saga_completed_total'); return saga;
      } catch (error) { return compensate(saga, ['REFUND', 'RELEASE'], toError(error)); }
    }
    return saga;
  } catch (error) {
    const failure = toError(error); metrics.increment('saga_failed_total');
    return record(saga.sagaId, saga.state, { type: 'SAGA_PAUSED_FOR_RECONCILIATION', status: 'FAILED', detail: failure.code }, failure);
  }
};

const typeDefs = /* GraphQL */ `
  enum ConnectorState { AVAILABLE RESERVED CHARGING OUT_OF_SERVICE }
  enum SagaState { PENDING RESERVED CHARGED ACTIVATING COMPLETED COMPENSATING COMPENSATED COMPENSATION_FAILED }
  type Connector { connectorId: ID!, stationId: ID!, state: ConnectorState!, powerKw: Float!, isFastCharge: Boolean!, reservationSagaId: ID, reservationFleetId: ID, reservationExpiresAt: Float }
  type Station { stationId: ID!, connectors: [Connector!]! }
  type Wallet { fleetId: ID!, balanceCents: Int!, currency: String!, updatedAt: String! }
  type Telemetry { sessionId: ID!, connectorId: ID!, stationId: ID!, powerKw: Float!, energyKwh: Float!, timestamp: String! }
  type FeatureFlag { name: String!, value: Boolean!, environment: String!, updatedAt: String!, updatedBy: String! }
  type SagaEvent { at: String!, type: String!, status: String!, detail: String }
  type DomainError { code: String!, message: String!, retryable: Boolean! }
  type SagaTransaction { sagaId: ID!, correlationId: ID!, idempotencyKey: String!, environment: String!, fleetId: ID!, stationId: ID!, connectorId: ID!, estimatedCostCents: Int!, state: SagaState!, sessionId: ID, error: DomainError, events: [SagaEvent!]!, createdAt: String!, updatedAt: String!, compensationPlan: [String!], compensationCompleted: [String!] }
  type SagaResult { saga: SagaTransaction!, correlationId: ID!, error: DomainError }
  input ReserveAndStartInput { fleetId: ID!, stationId: ID!, connectorId: ID!, idempotencyKey: String!, fastChargeBoost: Boolean = false }
  type Query { environment: String!, stations: [Station!]!, station(stationId: ID!): Station, connectorAvailability(connectorId: ID!): Connector, telemetry(sessionId: ID!): [Telemetry!]!, fleetWallet(fleetId: ID!): Wallet, sagaTransactions: [SagaTransaction!]!, sagaTransaction(sagaId: ID!): SagaTransaction, featureFlags: [FeatureFlag!]! }
  type Mutation { reserveAndStartCharging(input: ReserveAndStartInput!): SagaResult!, closeCharging(sagaId: ID!): SagaTransaction!, setFeatureFlag(name: String!, value: Boolean!): FeatureFlag!, reconcileSagas: [SagaTransaction!]! }
`;

interface Context { correlationId: string; role: string; }
const schema = createSchema({ typeDefs, resolvers: {
  Query: {
    environment: () => environment,
    stations: async () => (await stationClient.request<{ stations: unknown[] }>('/stations')).stations,
    station: async (_: unknown, args: { stationId: string }) => (await stationClient.request<{ stations: Array<{ stationId: string }> }>('/stations')).stations.find((station) => station.stationId === args.stationId) ?? null,
    connectorAvailability: async (_: unknown, args: { connectorId: string }) => (await stationClient.request<{ connector: unknown }>(`/connectors/${args.connectorId}`)).connector,
    fleetWallet: async (_: unknown, args: { fleetId: string }) => (await billingClient.request<{ wallet: unknown }>(`/wallets/${args.fleetId}`)).wallet,
    telemetry: async (_: unknown, args: { sessionId: string }) => (await dispatchClient.request<{ telemetry: unknown[] }>(`/sessions/${args.sessionId}/telemetry`)).telemetry,
    sagaTransactions: async () => (await db.send(new ScanCommand({ TableName: sagaTable, FilterExpression: 'begins_with(PK, :prefix)', ExpressionAttributeValues: { ':prefix': 'SAGA#' } }))).Items ?? [],
    sagaTransaction: async (_: unknown, args: { sagaId: string }) => (await getSaga(args.sagaId)) ?? null,
    featureFlags: async () => {
      await getFlags(); const result = await db.send(new ScanCommand({ TableName: flagsTable })); return result.Items ?? [];
    }
  },
  Connector: { reservationSagaId: (connector: { reservation?: { sagaId?: string } }) => connector.reservation?.sagaId, reservationFleetId: (connector: { reservation?: { fleetId?: string } }) => connector.reservation?.fleetId, reservationExpiresAt: (connector: { reservation?: { expiresAt?: number } }) => connector.reservation?.expiresAt },
  Mutation: {
    reserveAndStartCharging: async (_: unknown, args: { input: { fleetId: string; stationId: string; connectorId: string; idempotencyKey: string; fastChargeBoost?: boolean } }, context: Context) => {
      if (!/^[-a-zA-Z0-9_]{8,128}$/.test(args.input.idempotencyKey)) throw new GraphQLError('idempotencyKey inválida.', { extensions: { code: 'INVALID_IDEMPOTENCY_KEY' } });
      const flags = await getFlags(); const estimatedCostCents = flags.ENABLE_DYNAMIC_SURGE_PRICING ? 36_000 : 30_000;
      const initial = await getSagaByIdempotency(args.input.idempotencyKey) ?? await createSaga({ ...args.input, correlationId: context.correlationId, estimatedCostCents });
      const saga = await executeSaga(initial, { ...flags, ENABLE_FAST_CHARGE_BOOST: flags.ENABLE_FAST_CHARGE_BOOST && Boolean(args.input.fastChargeBoost) });
      const failure = saga.state === 'COMPLETED' ? undefined : saga.error;
      log({ service: 'graphql-gateway', environment, operation: 'reserve_and_start_charging', status: saga.state === 'COMPLETED' ? 'SUCCEEDED' : 'FAILED', correlation_id: saga.correlationId, saga_id: saga.sagaId, error_code: failure?.code });
      return { saga, correlationId: saga.correlationId, error: failure };
    },
    closeCharging: async (_: unknown, args: { sagaId: string }, context: Context) => {
      const saga = await getSaga(args.sagaId);
      if (!saga?.sessionId) throw new GraphQLError('SAGA o sesión no encontrada.', { extensions: { code: 'SAGA_NOT_FOUND' } });
      await dispatchClient.request(`/sessions/${saga.sessionId}/stop`, { method: 'POST', correlationId: context.correlationId, body: {} });
      await stationClient.request(`/reservations/${saga.connectorId}/close`, { method: 'POST', correlationId: context.correlationId, body: { sagaId: saga.sagaId } });
      return record(saga.sagaId, 'COMPLETED', { type: 'CHARGE_STOPPED', status: 'SUCCEEDED' });
    },
    setFeatureFlag: async (_: unknown, args: { name: string; value: boolean }, context: Context) => {
      if (!['admin-demo', 'platform-admin'].includes(context.role)) throw new GraphQLError('No autorizado para administrar flags.', { extensions: { code: 'FORBIDDEN' } });
      try { return await updateFlag(args.name, args.value, context.role); } catch (error) { const domain = toError(error); throw new GraphQLError(domain.message, { extensions: { code: domain.code } }); }
    },
    reconcileSagas: async (_: unknown, _args: unknown, context: Context) => {
      if (!['admin-demo', 'platform-admin'].includes(context.role)) throw new GraphQLError('No autorizado.', { extensions: { code: 'FORBIDDEN' } });
      const records = (await db.send(new ScanCommand({ TableName: sagaTable, FilterExpression: '#state IN (:pending, :reserved, :charged, :activating, :compensating, :failed)', ExpressionAttributeNames: { '#state': 'state' }, ExpressionAttributeValues: { ':pending': 'PENDING', ':reserved': 'RESERVED', ':charged': 'CHARGED', ':activating': 'ACTIVATING', ':compensating': 'COMPENSATING', ':failed': 'COMPENSATION_FAILED' } }))).Items as SagaItem[] ?? [];
      const flags = await getFlags(); return Promise.all(records.map((saga) => executeSaga(saga, flags)));
    }
  }
} });

const app = Fastify({ logger: false, requestIdHeader: 'x-correlation-id', bodyLimit: 1024 * 64 });
const allowedOrigins = (process.env.WEB_ORIGIN ?? 'http://localhost:5173').split(',');
await app.register(cors, { origin: (origin, callback) => callback(null, !origin || allowedOrigins.includes(origin)), methods: ['GET', 'POST'], allowedHeaders: ['content-type', 'x-correlation-id', 'x-aegisvolt-role'] });
const yoga = createYoga<Context>({ schema, graphqlEndpoint: '/graphql', graphiql: process.env.NODE_ENV !== 'production', context: ({ request }) => ({ correlationId: request.headers.get('x-correlation-id') ?? randomUUID(), role: request.headers.get('x-aegisvolt-role') ?? (process.env.DEMO_AUTH === 'true' ? 'operator-demo' : 'anonymous') }) });
app.route({ method: ['GET', 'POST'], url: '/graphql', handler: async (request, reply) => {
  const response = await yoga.fetch('http://gateway.local/graphql', { method: request.method, headers: request.headers as Record<string, string>, body: request.method === 'GET' ? undefined : JSON.stringify(request.body) });
  response.headers.forEach((value, name) => reply.header(name, value)); reply.code(response.status).send(await response.text());
} });
app.get('/health/live', async () => ({ status: 'ok', service: 'graphql-gateway', environment }));
app.get('/health/ready', async (_request, reply) => {
  try { await Promise.all([stationClient.request('/health/ready', { safeRetry: false }), billingClient.request('/health/ready', { safeRetry: false }), dispatchClient.request('/health/ready', { safeRetry: false })]); return { status: 'ready', environment }; }
  catch { return reply.code(503).send({ status: 'not_ready', environment }); }
});
app.get('/metrics', async (_request, reply) => reply.type('text/plain').send(metrics.prometheus()));
const port = Number(process.env.PORT ?? 4000);
app.listen({ port, host: '0.0.0.0' }).catch((error) => { console.error(error); process.exit(1); });
