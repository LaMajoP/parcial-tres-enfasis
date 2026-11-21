import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';

const endpoint = process.env.GRAPHQL_URL ?? 'http://localhost:4000/graphql';
async function gql<T>(query: string, variables: Record<string, unknown> = {}): Promise<T> {
  const response = await fetch(endpoint, { method: 'POST', headers: { 'content-type': 'application/json', 'x-aegisvolt-role': 'admin-demo', 'x-correlation-id': randomUUID() }, body: JSON.stringify({ query, variables }) });
  const body = await response.json() as { data?: T; errors?: unknown }; if (!response.ok || body.errors || !body.data) throw new Error(JSON.stringify(body)); return body.data;
}
const mutation = `mutation Start($input: ReserveAndStartInput!) { reserveAndStartCharging(input:$input) { correlationId saga { sagaId state sessionId estimatedCostCents error { code } events { type status } } } }`;

describe('SAGA contra DynamoDB Local y servicios reales', () => {
  it('termina rechazos definitivos sin cobro, activación ni reconciliación', async () => {
    const billing = process.env.BILLING_SERVICE_URL ?? 'http://localhost:3002';
    const dispatch = process.env.DISPATCH_SERVICE_URL ?? 'http://localhost:3003';
    const before = await gql<{ fleetWallet: { balanceCents: number } }>('query { fleetWallet(fleetId:"fleet-demo"){ balanceCents } }');
    const rejected = [
      { stationId: 'station-bogota-01', connectorId: 'connector-inexistente', expected: 'CONNECTOR_NOT_FOUND' },
      { stationId: 'station-chia-01', connectorId: 'connector-03', expected: 'CONNECTOR_UNAVAILABLE' },
      { stationId: 'station-chia-01', connectorId: 'connector-01', expected: 'CONNECTOR_STATION_MISMATCH' }
    ];
    for (const item of rejected) {
      const idempotencyKey = `it-rejected-${randomUUID()}`;
      const { expected, ...reservation } = item;
      const result = await gql<{ reserveAndStartCharging: { saga: { state: string; error?: { code: string }; events: Array<{ type: string }> } } }>(mutation, { input: { fleetId: 'fleet-demo', ...reservation, idempotencyKey } });
      const saga = result.reserveAndStartCharging.saga;
      expect(saga.state).toBe('COMPENSATED');
      expect(saga.error?.code).toBe(expected);
      expect(saga.events.map((event) => event.type)).toContain('SAGA_TERMINATED');
      expect(saga.events.map((event) => event.type)).not.toContain('SAGA_PAUSED_FOR_RECONCILIATION');
      const movements = await (await fetch(`${billing}/movements/fleet-demo`)).json() as { movements: Array<{ idempotencyKey: string }> };
      expect(movements.movements.some((movement) => movement.idempotencyKey === `${idempotencyKey}:debit`)).toBe(false);
      const sessions = await (await fetch(`${dispatch}/sessions`)).json() as { sessions: Array<{ idempotencyKey: string }> };
      expect(sessions.sessions.some((session) => session.idempotencyKey === idempotencyKey)).toBe(false);
    }
    const after = await gql<{ fleetWallet: { balanceCents: number } }>('query { fleetWallet(fleetId:"fleet-demo"){ balanceCents } }');
    expect(after.fleetWallet.balanceCents).toBe(before.fleetWallet.balanceCents);
  });
  it('un saldo insuficiente libera la reserva sin activar ni cobrar', async () => {
    const billing = process.env.BILLING_SERVICE_URL ?? 'http://localhost:3002';
    const seeded = await fetch(`${billing}/seed`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ fleetId: 'fleet-low', balanceCents: 1 }) });
    expect(seeded.ok).toBe(true);
    const result = await gql<{ reserveAndStartCharging: { saga: { state: string; events: Array<{ type: string }> } } }>(mutation, { input: { fleetId: 'fleet-low', stationId: 'station-chia-01', connectorId: 'connector-04', idempotencyKey: `it-low-${randomUUID()}` } });
    expect(result.reserveAndStartCharging.saga.state).toBe('COMPENSATED');
    expect(result.reserveAndStartCharging.saga.events.map((event) => event.type)).toContain('RELEASE_SUCCEEDED');
    const availability = await gql<{ connectorAvailability: { state: string } }>('query { connectorAvailability(connectorId:"connector-04"){ state } }');
    expect(availability.connectorAvailability.state).toBe('AVAILABLE');
  });
  it('todo conector anunciado AVAILABLE se reserva usando el mismo par estación/conector', async () => {
    const idempotencyKey = `it-success-${randomUUID()}`;
    const inventory = await gql<{ stations: Array<{ stationId: string; connectors: Array<{ connectorId: string; state: string }> }> }>('query { stations { stationId connectors { connectorId state } } }');
    const station = inventory.stations.find((item) => item.stationId === 'station-bogota-01');
    const connector = station?.connectors.find((item) => item.connectorId === 'connector-02');
    expect(connector?.state).toBe('AVAILABLE');
    const result = await gql<{ reserveAndStartCharging: { correlationId: string; saga: { sagaId: string; state: string; sessionId?: string; events: Array<{ type: string }> } } }>(mutation, { input: { fleetId: 'fleet-demo', stationId: station!.stationId, connectorId: connector!.connectorId, idempotencyKey } });
    const { saga, correlationId } = result.reserveAndStartCharging;
    expect(saga.state).toBe('COMPLETED'); expect(saga.sessionId).toBeTruthy(); expect(saga.events.map((event) => event.type)).toContain('DEBIT_SUCCEEDED');
    const lookup = await gql<{ sagaTransaction: { correlationId: string; state: string } }>('query($id:ID!){ sagaTransaction(sagaId:$id){ correlationId state } }', { id: saga.sagaId });
    expect(lookup.sagaTransaction.correlationId).toBe(correlationId); expect(lookup.sagaTransaction.state).toBe('COMPLETED');
    const charging = await gql<{ connectorAvailability: { state: string; reservationExpiresAt?: number } }>('query { connectorAvailability(connectorId:"connector-02"){ state reservationExpiresAt } }');
    expect(charging.connectorAvailability.state).toBe('CHARGING');
    expect(charging.connectorAvailability.reservationExpiresAt).toBeNull();
    await gql('mutation Close($id:ID!){ closeCharging(sagaId:$id){ state } }', { id: saga.sagaId });
    const availableAgain = await gql<{ connectorAvailability: { state: string } }>('query { connectorAvailability(connectorId:"connector-02"){ state } }');
    expect(availableAgain.connectorAvailability.state).toBe('AVAILABLE');
  });
  it('repetir la idempotency key no crea una segunda SAGA', async () => {
    const input = { fleetId: 'fleet-demo', stationId: 'station-bogota-01', connectorId: 'connector-01', idempotencyKey: `it-duplicate-${randomUUID()}` };
    const first = await gql<{ reserveAndStartCharging: { saga: { sagaId: string; state: string } } }>(mutation, { input });
    const second = await gql<{ reserveAndStartCharging: { saga: { sagaId: string; state: string } } }>(mutation, { input });
    expect(second.reserveAndStartCharging.saga.sagaId).toBe(first.reserveAndStartCharging.saga.sagaId);
    expect(second.reserveAndStartCharging.saga.state).toBe('COMPLETED');
    const billing = process.env.BILLING_SERVICE_URL ?? 'http://localhost:3002';
    const movements = await (await fetch(`${billing}/movements/fleet-demo`)).json() as { movements: Array<{ idempotencyKey: string; type: string }> };
    expect(movements.movements.filter((movement) => movement.idempotencyKey === `${input.idempotencyKey}:debit` && movement.type === 'DEBIT')).toHaveLength(1);
    await gql('mutation Close($id:ID!){ closeCharging(sagaId:$id){ state } }', { id: first.reserveAndStartCharging.saga.sagaId });
  });
  it('una falla física reembolsa antes de liberar el conector', async () => {
    await gql('mutation { setFeatureFlag(name:"SIMULATE_CHARGER_HARDWARE_FAULT",value:true){ value } }');
    const result = await gql<{ reserveAndStartCharging: { saga: { state: string; events: Array<{ type: string; status: string }> } } }>(mutation, { input: { fleetId: 'fleet-demo', stationId: 'station-bogota-01', connectorId: 'connector-01', idempotencyKey: `it-fault-${randomUUID()}` } });
    const events = result.reserveAndStartCharging.saga.events.map((event) => event.type);
    expect(result.reserveAndStartCharging.saga.state).toBe('COMPENSATED');
    expect(events.indexOf('REFUND_SUCCEEDED')).toBeLessThan(events.indexOf('RELEASE_SUCCEEDED'));
    await gql('mutation { setFeatureFlag(name:"SIMULATE_CHARGER_HARDWARE_FAULT",value:false){ value } }');
  });
  it('un timeout de dispatch falla de forma terminal sin dejar sesión activa', async () => {
    const dispatch = process.env.DISPATCH_SERVICE_URL ?? 'http://localhost:3003';
    const idempotencyKey = `it-timeout-${randomUUID()}`;
    const response = await fetch(`${dispatch}/activate`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ sagaId: randomUUID(), correlationId: randomUUID(), idempotencyKey, environment: 'dev', fleetId: 'fleet-demo', stationId: 'station-bogota-01', connectorId: 'connector-02', simulateTimeout: true })
    });
    expect(response.status).toBe(502);
    expect((await response.json() as { code: string }).code).toBe('HARDWARE_TIMEOUT');
    const sessions = await (await fetch(`${dispatch}/sessions`)).json() as { sessions: Array<{ idempotencyKey: string; state: string }> };
    expect(sessions.sessions.find((session) => session.idempotencyKey === idempotencyKey)?.state).toBe('FAILED');
  });
});
