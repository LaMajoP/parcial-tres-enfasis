import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';

const station = process.env.STATION_SERVICE_URL ?? 'http://localhost:3001';
describe('resiliencia de reserva', () => {
  it('dos flotas no adquieren el mismo conector de forma concurrente', async () => {
    const inventory = await (await fetch(`${station}/stations`)).json() as { stations: Array<{ stationId: string; connectors: Array<{ connectorId: string; state: string }> }> };
    const available = inventory.stations.flatMap((item) => item.connectors.filter((connector) => connector.state === 'AVAILABLE').map((connector) => ({ stationId: item.stationId, connectorId: connector.connectorId })))[0];
    expect(available).toBeTruthy();
    const attempts = ['fleet-a', 'fleet-b'].map((fleetId) => ({ fleetId, sagaId: randomUUID(), correlationId: randomUUID(), idempotencyKey: `race-${randomUUID()}` }));
    const responses = await Promise.all(attempts.map((attempt) => fetch(`${station}/reservations`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ environment: 'dev', ...available!, ...attempt, expiresInSeconds: 300 }) })));
    try {
      expect(responses.filter((response) => response.status === 201)).toHaveLength(1);
      expect(responses.filter((response) => response.status === 409)).toHaveLength(1);
    } finally {
      const winner = attempts[responses.findIndex((response) => response.status === 201)];
      if (winner) {
        const released = await fetch(`${station}/reservations/${available!.connectorId}/release`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ sagaId: winner.sagaId, correlationId: winner.correlationId }) });
        expect(released.ok).toBe(true);
      }
    }
  });
});
