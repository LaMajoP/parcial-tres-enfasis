import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';

const station = process.env.STATION_SERVICE_URL ?? 'http://localhost:3001';
const base = { environment: 'dev', stationId: 'station-chia-01', connectorId: 'connector-04', fleetId: 'fleet-demo' };
describe('resiliencia de reserva', () => {
  it('dos flotas no adquieren el mismo conector de forma concurrente', async () => {
    const calls = ['fleet-a', 'fleet-b'].map((fleetId) => fetch(`${station}/reservations`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...base, fleetId, sagaId: randomUUID(), correlationId: randomUUID(), idempotencyKey: `race-${randomUUID()}`, expiresInSeconds: 300 }) }));
    const responses = await Promise.all(calls);
    expect(responses.filter((response) => response.status === 201).length).toBe(1);
    expect(responses.filter((response) => response.status === 409).length).toBe(1);
  });
});
