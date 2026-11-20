import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { GetCommand, PutCommand, ScanCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { DomainError, type Connector, type Environment, ReserveConnectorSchema, dynamoDocumentClient, epochSeconds, nowIso, parseEnvironment, tableName } from '@aegisvolt/contracts';
import { Metrics, log } from '@aegisvolt/shared-observability';

const environment = parseEnvironment();
const table = tableName('reservations', environment);
const db = dynamoDocumentClient();
const metrics = new Metrics('station-reservation-service', environment);
const app = Fastify({ logger: false, requestIdHeader: 'x-correlation-id' });

type ConnectorItem = Connector & { PK: string; SK: string; expiresAt?: number; sagaId?: string; fleetId?: string; updatedAt: string };
const key = (connectorId: string) => ({ PK: `CONNECTOR#${connectorId}`, SK: 'META' });
const asConnector = (item: ConnectorItem): Connector => ({
  connectorId: item.connectorId, stationId: item.stationId, state: item.state, powerKw: item.powerKw, isFastCharge: item.isFastCharge,
  reservation: item.sagaId && item.fleetId && item.expiresAt ? { sagaId: item.sagaId, fleetId: item.fleetId, expiresAt: item.expiresAt } : undefined
});

const getConnector = async (connectorId: string): Promise<ConnectorItem | undefined> => {
  const result = await db.send(new GetCommand({ TableName: table, Key: key(connectorId), ConsistentRead: true }));
  return result.Item as ConnectorItem | undefined;
};

const serviceError = (error: unknown): DomainError => error instanceof DomainError ? error : new DomainError('RESERVATION_UNAVAILABLE', 'No fue posible completar la reserva.', true);

app.get('/health/live', async () => ({ status: 'ok', service: 'station-reservation-service', environment }));
app.get('/health/ready', async (_request, reply) => {
  try { await db.send(new ScanCommand({ TableName: table, Limit: 1, Select: 'COUNT' })); return { status: 'ready', table }; }
  catch { return reply.code(503).send({ status: 'not_ready', table }); }
});
app.get('/metrics', async (_request, reply) => reply.type('text/plain').send(metrics.prometheus()));

app.get('/stations', async () => {
  const response = await db.send(new ScanCommand({ TableName: table, FilterExpression: 'begins_with(PK, :prefix)', ExpressionAttributeValues: { ':prefix': 'CONNECTOR#' } }));
  const connectors = (response.Items ?? []).map((item) => asConnector(item as ConnectorItem));
  const stations = Object.values(connectors.reduce<Record<string, { stationId: string; connectors: Connector[] }>>((all, connector) => {
    all[connector.stationId] ??= { stationId: connector.stationId, connectors: [] }; all[connector.stationId].connectors.push(connector); return all;
  }, {}));
  return { stations };
});

app.get('/connectors/:connectorId', async (request, reply) => {
  const item = await getConnector((request.params as { connectorId: string }).connectorId);
  if (!item) return reply.code(404).send({ code: 'CONNECTOR_NOT_FOUND', message: 'Conector no encontrado.' });
  return { connector: asConnector(item) };
});

app.post('/seed', async (_request, reply) => {
  if (process.env.DEMO_MODE !== 'true') return reply.code(404).send({ code: 'NOT_FOUND', message: 'Ruta de semilla deshabilitada.' });
  const connectors: Array<Omit<ConnectorItem, 'PK' | 'SK' | 'updatedAt'>> = [
    { connectorId: 'connector-01', stationId: 'station-bogota-01', state: 'AVAILABLE', powerKw: 150, isFastCharge: true },
    { connectorId: 'connector-02', stationId: 'station-bogota-01', state: 'AVAILABLE', powerKw: 50, isFastCharge: false },
    { connectorId: 'connector-03', stationId: 'station-chia-01', state: 'OUT_OF_SERVICE', powerKw: 150, isFastCharge: true },
    { connectorId: 'connector-04', stationId: 'station-chia-01', state: 'AVAILABLE', powerKw: 50, isFastCharge: false }
  ];
  let created = 0;
  for (const connector of connectors) {
    try { await db.send(new PutCommand({ TableName: table, Item: { ...connector, ...key(connector.connectorId), updatedAt: nowIso() }, ConditionExpression: 'attribute_not_exists(PK)' })); created += 1; }
    catch (error: unknown) { if ((error as { name?: string }).name !== 'ConditionalCheckFailedException') throw error; }
  }
  return { created, total: connectors.length };
});

app.post('/reservations', async (request, reply) => {
  const started = Date.now();
  let context: { correlationId?: string; sagaId?: string } = {};
  try {
    const body = ReserveConnectorSchema.parse(request.body);
    context = body;
    const existing = await getConnector(body.connectorId);
    if (!existing) throw new DomainError('CONNECTOR_NOT_FOUND', 'El conector solicitado no existe.');
    if (existing.sagaId === body.sagaId && existing.state === 'RESERVED') return { reservation: asConnector(existing), idempotent: true };
    if (body.requiresFastCharge && !existing.isFastCharge) throw new DomainError('FAST_CHARGE_REQUIRED', 'La flota requiere un conector de ultracarga.');
    const expiresAt = epochSeconds() + body.expiresInSeconds;
    try {
      await db.send(new UpdateCommand({
        TableName: table, Key: key(body.connectorId),
        UpdateExpression: 'SET #state = :reserved, sagaId = :sagaId, fleetId = :fleetId, expiresAt = :expiresAt, updatedAt = :updatedAt',
        ConditionExpression: '#state = :available OR (#state = :reserved AND sagaId = :sagaId)',
        ExpressionAttributeNames: { '#state': 'state' },
        ExpressionAttributeValues: { ':available': 'AVAILABLE', ':reserved': 'RESERVED', ':sagaId': body.sagaId, ':fleetId': body.fleetId, ':expiresAt': expiresAt, ':updatedAt': nowIso() }
      }));
    } catch (error: unknown) {
      const after = await getConnector(body.connectorId);
      if (after?.sagaId === body.sagaId && after.state === 'RESERVED') return { reservation: asConnector(after), idempotent: true };
      if ((error as { name?: string }).name === 'ConditionalCheckFailedException') throw new DomainError('CONNECTOR_UNAVAILABLE', 'El conector ya está ocupado o no está disponible.');
      throw error;
    }
    const reserved = await getConnector(body.connectorId);
    metrics.increment('ReservationSucceeded');
    log({ service: 'station-reservation-service', environment, operation: 'reserve_connector', status: 'SUCCEEDED', correlation_id: body.correlationId, saga_id: body.sagaId, duration_ms: Date.now() - started });
    return reply.code(201).send({ reservation: asConnector(reserved!), idempotent: false });
  } catch (error) {
    const failure = serviceError(error); metrics.increment('ReservationFailed');
    log({ level: 'ERROR', service: 'station-reservation-service', environment, operation: 'reserve_connector', status: 'FAILED', correlation_id: context.correlationId, saga_id: context.sagaId, error_code: failure.code, duration_ms: Date.now() - started });
    return reply.code(failure.code === 'CONNECTOR_UNAVAILABLE' ? 409 : 400).send(failure);
  }
});

app.post('/reservations/:connectorId/release', async (request, reply) => {
  const connectorId = (request.params as { connectorId: string }).connectorId;
  const body = request.body as { sagaId?: string; correlationId?: string };
  if (!body.sagaId) return reply.code(400).send({ code: 'INVALID_REQUEST', message: 'sagaId es obligatorio.' });
  try {
    await db.send(new UpdateCommand({
      TableName: table, Key: key(connectorId),
      UpdateExpression: 'SET #state = :available, updatedAt = :updatedAt REMOVE sagaId, fleetId, expiresAt',
      ConditionExpression: '#state = :reserved AND sagaId = :sagaId',
      ExpressionAttributeNames: { '#state': 'state' },
      ExpressionAttributeValues: { ':reserved': 'RESERVED', ':available': 'AVAILABLE', ':sagaId': body.sagaId, ':updatedAt': nowIso() }
    }));
  } catch (error: unknown) {
    const current = await getConnector(connectorId);
    if (current?.state === 'AVAILABLE') return { released: true, idempotent: true };
    if ((error as { name?: string }).name === 'ConditionalCheckFailedException') return reply.code(409).send({ code: 'RESERVATION_OWNERSHIP_MISMATCH', message: 'No se puede liberar una reserva de otra saga.' });
    throw error;
  }
  log({ service: 'station-reservation-service', environment, operation: 'release_connector', status: 'SUCCEEDED', correlation_id: body.correlationId, saga_id: body.sagaId });
  return { released: true, idempotent: false };
});

app.post('/reservations/:connectorId/activate', async (request, reply) => {
  const connectorId = (request.params as { connectorId: string }).connectorId;
  const body = request.body as { sagaId?: string; sessionId?: string };
  if (!body.sagaId || !body.sessionId) return reply.code(400).send({ code: 'INVALID_REQUEST', message: 'sagaId y sessionId son obligatorios.' });
  try {
    await db.send(new UpdateCommand({ TableName: table, Key: key(connectorId), UpdateExpression: 'SET #state = :charging, sessionId = :sessionId, updatedAt = :updatedAt', ConditionExpression: '#state = :reserved AND sagaId = :sagaId', ExpressionAttributeNames: { '#state': 'state' }, ExpressionAttributeValues: { ':charging': 'CHARGING', ':reserved': 'RESERVED', ':sagaId': body.sagaId, ':sessionId': body.sessionId, ':updatedAt': nowIso() } }));
  } catch (error: unknown) {
    const current = await getConnector(connectorId);
    if (current?.state === 'CHARGING' && current.sagaId === body.sagaId) return { activated: true, idempotent: true };
    if ((error as { name?: string }).name === 'ConditionalCheckFailedException') return reply.code(409).send({ code: 'RESERVATION_OWNERSHIP_MISMATCH', message: 'La reserva no pertenece a esta SAGA.' });
    throw error;
  }
  return { activated: true, idempotent: false };
});

app.post('/reservations/:connectorId/close', async (request, reply) => {
  const connectorId = (request.params as { connectorId: string }).connectorId;
  const body = request.body as { sagaId?: string };
  if (!body.sagaId) return reply.code(400).send({ code: 'INVALID_REQUEST', message: 'sagaId es obligatorio.' });
  try {
    await db.send(new UpdateCommand({ TableName: table, Key: key(connectorId), UpdateExpression: 'SET #state = :available, updatedAt = :updatedAt REMOVE sagaId, fleetId, expiresAt, sessionId', ConditionExpression: '#state = :charging AND sagaId = :sagaId', ExpressionAttributeNames: { '#state': 'state' }, ExpressionAttributeValues: { ':charging': 'CHARGING', ':available': 'AVAILABLE', ':sagaId': body.sagaId, ':updatedAt': nowIso() } }));
  } catch (error: unknown) {
    const current = await getConnector(connectorId);
    if (current?.state === 'AVAILABLE') return { closed: true, idempotent: true };
    if ((error as { name?: string }).name === 'ConditionalCheckFailedException') return reply.code(409).send({ code: 'RESERVATION_OWNERSHIP_MISMATCH', message: 'La sesión no pertenece a esta SAGA.' });
    throw error;
  }
  return { closed: true, idempotent: false };
});

app.post('/reconcile-expired', async () => {
  const response = await db.send(new ScanCommand({ TableName: table, FilterExpression: '#state = :reserved AND expiresAt < :now', ExpressionAttributeNames: { '#state': 'state' }, ExpressionAttributeValues: { ':reserved': 'RESERVED', ':now': epochSeconds() } }));
  let released = 0;
  for (const item of response.Items as ConnectorItem[] ?? []) {
    try {
      await db.send(new UpdateCommand({ TableName: table, Key: key(item.connectorId), UpdateExpression: 'SET #state = :available, updatedAt = :updatedAt REMOVE sagaId, fleetId, expiresAt', ConditionExpression: '#state = :reserved AND sagaId = :sagaId AND expiresAt < :now', ExpressionAttributeNames: { '#state': 'state' }, ExpressionAttributeValues: { ':available': 'AVAILABLE', ':reserved': 'RESERVED', ':sagaId': item.sagaId, ':now': epochSeconds(), ':updatedAt': nowIso() } }));
      released += 1;
    } catch { /* otra operación ganó la reconciliación; no se libera una reserva nueva */ }
  }
  return { released };
});

const port = Number(process.env.PORT ?? 3001);
app.listen({ port, host: '0.0.0.0' }).catch((error) => { console.error(error); process.exit(1); });
