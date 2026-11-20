import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { GetCommand, PutCommand, QueryCommand, ScanCommand, TransactWriteCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { ActivateChargingSchema, DomainError, type DispatchSession, type Environment, type Telemetry, dynamoDocumentClient, nowIso, parseEnvironment, tableName } from '@aegisvolt/contracts';
import { Metrics, log } from '@aegisvolt/shared-observability';

const environment = parseEnvironment();
const table = tableName('dispatch', environment);
const db = dynamoDocumentClient();
const metrics = new Metrics('energy-dispatch-service', environment);
const app = Fastify({ logger: false, requestIdHeader: 'x-correlation-id' });
type ActivationRecord = { PK: string; SK: string; sessionId: string; state: string; errorCode?: string };
type SessionItem = DispatchSession & { PK: string; SK: string; idempotencyKey: string; updatedAt: string };
const activationKey = (idempotencyKey: string) => ({ PK: `ACTIVATION#${idempotencyKey}`, SK: 'META' });
const sessionKey = (sessionId: string) => ({ PK: `SESSION#${sessionId}`, SK: 'META' });

const getActivation = async (idempotencyKey: string): Promise<ActivationRecord | undefined> => (await db.send(new GetCommand({ TableName: table, Key: activationKey(idempotencyKey), ConsistentRead: true }))).Item as ActivationRecord | undefined;
const getSession = async (sessionId: string): Promise<SessionItem | undefined> => (await db.send(new GetCommand({ TableName: table, Key: sessionKey(sessionId), ConsistentRead: true }))).Item as SessionItem | undefined;

app.get('/health/live', async () => ({ status: 'ok', service: 'energy-dispatch-service', environment }));
app.get('/health/ready', async (_request, reply) => {
  try { await db.send(new ScanCommand({ TableName: table, Limit: 1, Select: 'COUNT' })); return { status: 'ready', table }; }
  catch { return reply.code(503).send({ status: 'not_ready', table }); }
});
app.get('/metrics', async (_request, reply) => reply.type('text/plain').send(metrics.prometheus()));
app.get('/sessions', async () => {
  const response = await db.send(new ScanCommand({ TableName: table, FilterExpression: 'begins_with(PK, :prefix) AND SK = :meta', ExpressionAttributeValues: { ':prefix': 'SESSION#', ':meta': 'META' } }));
  return { sessions: response.Items ?? [] };
});
app.get('/sessions/:sessionId/telemetry', async (request) => {
  const sessionId = (request.params as { sessionId: string }).sessionId;
  const response = await db.send(new QueryCommand({ TableName: table, KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)', ExpressionAttributeValues: { ':pk': `SESSION#${sessionId}`, ':sk': 'TELEMETRY#' } }));
  return { telemetry: response.Items ?? [] };
});

app.post('/sessions/:sessionId/stop', async (request, reply) => {
  const sessionId = (request.params as { sessionId: string }).sessionId;
  try {
    await db.send(new UpdateCommand({ TableName: table, Key: sessionKey(sessionId), UpdateExpression: 'SET #state = :stopped, updatedAt = :updatedAt', ConditionExpression: '#state = :active', ExpressionAttributeNames: { '#state': 'state' }, ExpressionAttributeValues: { ':active': 'ACTIVE', ':stopped': 'STOPPED', ':updatedAt': nowIso() } }));
  } catch (error: unknown) {
    const session = await getSession(sessionId);
    if (session?.state === 'STOPPED') return { stopped: true, idempotent: true };
    if ((error as { name?: string }).name === 'ConditionalCheckFailedException') return reply.code(409).send({ code: 'SESSION_NOT_ACTIVE', message: 'La sesión no está activa.' });
    throw error;
  }
  return { stopped: true, idempotent: false };
});

app.post('/activate', async (request, reply) => {
  const started = Date.now();
  let context: { correlationId?: string; sagaId?: string } = {};
  try {
    const body = ActivateChargingSchema.parse(request.body);
    context = body;
    const activation = await getActivation(body.idempotencyKey);
    if (activation) {
      const prior = await getSession(activation.sessionId);
      if (activation.state === 'FAILED') return reply.code(502).send({ code: activation.errorCode ?? 'HARDWARE_FAULT', message: 'La activación física simulada falló.', retryable: false, session: prior, idempotent: true });
      return { session: prior, idempotent: true };
    }
    const sessionId = randomUUID();
    const session: SessionItem = { ...sessionKey(sessionId), sessionId, sagaId: body.sagaId, connectorId: body.connectorId, stationId: body.stationId, fleetId: body.fleetId, state: 'STARTING', idempotencyKey: body.idempotencyKey, createdAt: nowIso(), updatedAt: nowIso() };
    await db.send(new TransactWriteCommand({ TransactItems: [
      { Put: { TableName: table, Item: { ...activationKey(body.idempotencyKey), sessionId, state: 'STARTING' }, ConditionExpression: 'attribute_not_exists(PK)' } },
      { Put: { TableName: table, Item: session, ConditionExpression: 'attribute_not_exists(PK)' } }
    ] }));
    if (body.simulateHardwareFault) {
      await db.send(new TransactWriteCommand({ TransactItems: [
        { Update: { TableName: table, Key: activationKey(body.idempotencyKey), UpdateExpression: 'SET #state = :failed, errorCode = :code', ExpressionAttributeNames: { '#state': 'state' }, ExpressionAttributeValues: { ':failed': 'FAILED', ':code': 'HARDWARE_FAULT' } } },
        { Update: { TableName: table, Key: sessionKey(sessionId), UpdateExpression: 'SET #state = :failed, updatedAt = :updatedAt', ExpressionAttributeNames: { '#state': 'state' }, ExpressionAttributeValues: { ':failed': 'FAILED', ':updatedAt': nowIso() } } }
      ] }));
      metrics.increment('ChargerHardwareFault');
      throw new DomainError('HARDWARE_FAULT', 'El cargador simuló una falla física no reintentable.');
    }
    // Un timeout simulado debe dejar un estado físico terminal. Retrasar una
    // activación y responder después del timeout del gateway produciría una
    // sesión fantasma: la SAGA compensaría mientras el cargador se activa.
    if (body.simulateTimeout) {
      await db.send(new TransactWriteCommand({ TransactItems: [
        { Update: { TableName: table, Key: activationKey(body.idempotencyKey), UpdateExpression: 'SET #state = :failed, errorCode = :code', ExpressionAttributeNames: { '#state': 'state' }, ExpressionAttributeValues: { ':failed': 'FAILED', ':code': 'HARDWARE_TIMEOUT' } } },
        { Update: { TableName: table, Key: sessionKey(sessionId), UpdateExpression: 'SET #state = :failed, updatedAt = :updatedAt', ExpressionAttributeNames: { '#state': 'state' }, ExpressionAttributeValues: { ':failed': 'FAILED', ':updatedAt': nowIso() } } }
      ] }));
      throw new DomainError('HARDWARE_TIMEOUT', 'El cargador simuló un timeout antes de activar.', true);
    }
    await db.send(new TransactWriteCommand({ TransactItems: [
      { Update: { TableName: table, Key: activationKey(body.idempotencyKey), UpdateExpression: 'SET #state = :active', ExpressionAttributeNames: { '#state': 'state' }, ExpressionAttributeValues: { ':active': 'ACTIVE' } } },
      { Update: { TableName: table, Key: sessionKey(sessionId), UpdateExpression: 'SET #state = :active, updatedAt = :updatedAt', ExpressionAttributeNames: { '#state': 'state' }, ExpressionAttributeValues: { ':active': 'ACTIVE', ':updatedAt': nowIso() } } }
    ] }));
    const telemetry: Telemetry[] = [0, 1, 2].map((sample) => ({ sessionId, connectorId: body.connectorId, stationId: body.stationId, powerKw: 48 + sample, energyKwh: Number((sample * 0.82).toFixed(2)), timestamp: new Date(Date.now() + sample * 1_000).toISOString() }));
    for (const sample of telemetry) await db.send(new PutCommand({ TableName: table, Item: { ...sample, PK: `SESSION#${sessionId}`, SK: `TELEMETRY#${sample.timestamp}` } }));
    const active = await getSession(sessionId);
    metrics.increment('ChargerActivation');
    log({ service: 'energy-dispatch-service', environment, operation: 'activate_charger', status: 'SUCCEEDED', correlation_id: body.correlationId, saga_id: body.sagaId, duration_ms: Date.now() - started });
    return reply.code(201).send({ session: active, telemetry, idempotent: false });
  } catch (error) {
    const domain = error instanceof DomainError ? error : new DomainError('DISPATCH_UNAVAILABLE', 'No fue posible activar el cargador.', true);
    log({ level: 'ERROR', service: 'energy-dispatch-service', environment, operation: 'activate_charger', status: 'FAILED', correlation_id: context.correlationId, saga_id: context.sagaId, error_code: domain.code, duration_ms: Date.now() - started });
    return reply.code(['HARDWARE_FAULT', 'HARDWARE_TIMEOUT'].includes(domain.code) ? 502 : 400).send(domain);
  }
});

const port = Number(process.env.PORT ?? 3003);
app.listen({ port, host: '0.0.0.0' }).catch((error) => { console.error(error); process.exit(1); });
