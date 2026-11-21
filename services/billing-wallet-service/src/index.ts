import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { GetCommand, PutCommand, ScanCommand, TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import { DebitWalletSchema, DomainError, demoWallet, type Movement, type Wallet, dynamoDocumentClient, nowIso, parseEnvironment, tableName } from '@aegisvolt/contracts';
import { Metrics, log } from '@aegisvolt/shared-observability';

const environment = parseEnvironment();
const table = tableName('billing', environment);
const db = dynamoDocumentClient();
const metrics = new Metrics('billing-wallet-service', environment);
const app = Fastify({ logger: false, requestIdHeader: 'x-correlation-id' });
type WalletItem = Wallet & { PK: string; SK: string };
type MovementItem = Movement & { PK: string; SK: string; fleetId: string };
const walletKey = (fleetId: string) => ({ PK: `WALLET#${fleetId}`, SK: 'CURRENT' });
const movementKey = (idempotencyKey: string) => ({ PK: `MOVEMENT#${idempotencyKey}`, SK: 'META' });

const getWallet = async (fleetId: string): Promise<WalletItem | undefined> => (await db.send(new GetCommand({ TableName: table, Key: walletKey(fleetId), ConsistentRead: true }))).Item as WalletItem | undefined;
const getMovement = async (idempotencyKey: string): Promise<MovementItem | undefined> => (await db.send(new GetCommand({ TableName: table, Key: movementKey(idempotencyKey), ConsistentRead: true }))).Item as MovementItem | undefined;
const errorPayload = (error: unknown): DomainError => error instanceof DomainError ? error : new DomainError('BILLING_UNAVAILABLE', 'La billetera no respondió.', true);

app.get('/health/live', async () => ({ status: 'ok', service: 'billing-wallet-service', environment }));
app.get('/health/ready', async (_request, reply) => {
  try { await db.send(new ScanCommand({ TableName: table, Limit: 1, Select: 'COUNT' })); return { status: 'ready', table }; }
  catch { return reply.code(503).send({ status: 'not_ready', table }); }
});
app.get('/metrics', async (_request, reply) => reply.type('text/plain').send(metrics.prometheus()));
app.get('/wallets/:fleetId', async (request, reply) => {
  const wallet = await getWallet((request.params as { fleetId: string }).fleetId);
  return wallet ? { wallet } : reply.code(404).send({ code: 'WALLET_NOT_FOUND', message: 'Billetera no encontrada.' });
});
app.get('/movements/:fleetId', async (request) => {
  const fleetId = (request.params as { fleetId: string }).fleetId;
  const response = await db.send(new ScanCommand({ TableName: table, FilterExpression: 'begins_with(PK, :prefix) AND fleetId = :fleetId', ExpressionAttributeValues: { ':prefix': 'MOVEMENT#', ':fleetId': fleetId } }));
  return { movements: (response.Items ?? []) as Movement[] };
});
app.post('/seed', async (request, reply) => {
  if (process.env.DEMO_MODE !== 'true') return reply.code(404).send({ code: 'NOT_FOUND', message: 'Ruta de semilla deshabilitada.' });
  const seed = (request.body ?? {}) as { fleetId?: string; balanceCents?: number };
  const fleetId = seed.fleetId ?? demoWallet.fleetId; const balanceCents = seed.balanceCents ?? demoWallet.balanceCents;
  if (!Number.isInteger(balanceCents) || balanceCents < 0) return reply.code(400).send({ code: 'INVALID_SEED', message: 'balanceCents debe ser un entero no negativo.' });
  const wallet: WalletItem = { ...walletKey(fleetId), fleetId, balanceCents, currency: 'COP', updatedAt: nowIso() };
  try { await db.send(new PutCommand({ TableName: table, Item: wallet, ConditionExpression: 'attribute_not_exists(PK)' })); return { created: true, wallet }; }
  catch (error: unknown) { if ((error as { name?: string }).name === 'ConditionalCheckFailedException') return { created: false, wallet: await getWallet(fleetId) }; throw error; }
});

const changeBalance = async (input: { fleetId: string; amountCents: number; sagaId: string; correlationId: string; idempotencyKey: string; reason: string }, type: 'DEBIT' | 'REFUND'): Promise<{ wallet: Wallet; movement: Movement; idempotent: boolean }> => {
  const actionKey = `${input.idempotencyKey}:${type.toLowerCase()}`;
  const prior = await getMovement(actionKey);
  if (prior) {
    const wallet = await getWallet(input.fleetId);
    if (!wallet) throw new DomainError('WALLET_NOT_FOUND', 'Billetera no encontrada.');
    return { wallet, movement: prior, idempotent: true };
  }
  const wallet = await getWallet(input.fleetId);
  if (!wallet) throw new DomainError('WALLET_NOT_FOUND', 'Billetera no encontrada.');
  if (type === 'DEBIT' && wallet.balanceCents < input.amountCents) throw new DomainError('INSUFFICIENT_FUNDS', 'Saldo insuficiente para autorizar la carga.');
  const movement: MovementItem = {
    ...movementKey(actionKey), movementId: randomUUID(), sagaId: input.sagaId, idempotencyKey: actionKey, amountCents: input.amountCents,
    type, createdAt: nowIso(), reference: input.reason, fleetId: input.fleetId
  };
  try {
    await db.send(new TransactWriteCommand({
      TransactItems: [
        {
          Update: {
            TableName: table, Key: walletKey(input.fleetId),
            UpdateExpression: 'SET balanceCents = balanceCents + :delta, updatedAt = :updatedAt',
            ConditionExpression: type === 'DEBIT' ? 'balanceCents >= :required' : 'attribute_exists(PK)',
            ExpressionAttributeValues: type === 'DEBIT'
              ? { ':delta': -input.amountCents, ':required': input.amountCents, ':updatedAt': nowIso() }
              : { ':delta': input.amountCents, ':updatedAt': nowIso() }
          }
        },
        { Put: { TableName: table, Item: movement, ConditionExpression: 'attribute_not_exists(PK)' } }
      ]
    }));
  } catch (error: unknown) {
    const after = await getMovement(actionKey);
    if (after) { const current = await getWallet(input.fleetId); return { wallet: current!, movement: after, idempotent: true }; }
    if ((error as { name?: string }).name === 'TransactionCanceledException' && type === 'DEBIT') throw new DomainError('INSUFFICIENT_FUNDS', 'Saldo insuficiente para autorizar la carga.');
    throw error;
  }
  const current = await getWallet(input.fleetId);
  return { wallet: current!, movement, idempotent: false };
};

app.post('/debits', async (request, reply) => {
  const started = Date.now();
  let context: { correlationId?: string; sagaId?: string } = {};
  try {
    const body = DebitWalletSchema.parse(request.body);
    context = body;
    const result = await changeBalance(body, 'DEBIT'); metrics.increment('WalletDebit');
    log({ service: 'billing-wallet-service', environment, operation: 'debit_wallet', status: 'SUCCEEDED', correlation_id: body.correlationId, saga_id: body.sagaId, duration_ms: Date.now() - started });
    return reply.code(result.idempotent ? 200 : 201).send(result);
  } catch (error) {
    const failure = errorPayload(error); metrics.increment('WalletDebitFailed');
    log({ level: 'ERROR', service: 'billing-wallet-service', environment, operation: 'debit_wallet', status: 'FAILED', correlation_id: context.correlationId, saga_id: context.sagaId, error_code: failure.code, duration_ms: Date.now() - started });
    return reply.code(failure.code === 'INSUFFICIENT_FUNDS' ? 422 : 400).send(failure);
  }
});

app.post('/refunds', async (request, reply) => {
  const started = Date.now();
  let context: { correlationId?: string; sagaId?: string } = {};
  try {
    const body = DebitWalletSchema.parse(request.body);
    context = body;
    const result = await changeBalance(body, 'REFUND'); metrics.increment('WalletRefund');
    log({ service: 'billing-wallet-service', environment, operation: 'refund_wallet', status: 'SUCCEEDED', correlation_id: body.correlationId, saga_id: body.sagaId, duration_ms: Date.now() - started });
    return reply.code(result.idempotent ? 200 : 201).send(result);
  } catch (error) {
    const failure = errorPayload(error);
    log({ level: 'ERROR', service: 'billing-wallet-service', environment, operation: 'refund_wallet', status: 'FAILED', correlation_id: context.correlationId, saga_id: context.sagaId, error_code: failure.code, duration_ms: Date.now() - started });
    return reply.code(400).send(failure);
  }
});

const port = Number(process.env.PORT ?? 3002);
app.listen({ port, host: '0.0.0.0' }).catch((error) => { console.error(error); process.exit(1); });
