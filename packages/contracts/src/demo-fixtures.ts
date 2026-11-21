import type { Connector, Wallet } from './index.js';

/**
 * Datos de demostración para DynamoDB Local. Son idempotentes: el bootstrap
 * solo crea una entidad si su clave todavía no existe y nunca sobrescribe un
 * estado operativo (RESERVED/CHARGING) ni un saldo ya usado.
 */
export const demoConnectors: readonly Omit<Connector, 'reservation'>[] = [
  { connectorId: 'connector-01', stationId: 'station-bogota-01', state: 'AVAILABLE', powerKw: 150, isFastCharge: true },
  { connectorId: 'connector-02', stationId: 'station-bogota-01', state: 'AVAILABLE', powerKw: 50, isFastCharge: false },
  { connectorId: 'connector-03', stationId: 'station-chia-01', state: 'OUT_OF_SERVICE', powerKw: 150, isFastCharge: true },
  { connectorId: 'connector-04', stationId: 'station-chia-01', state: 'AVAILABLE', powerKw: 50, isFastCharge: false }
];

export const demoWallet: Omit<Wallet, 'updatedAt'> = {
  fleetId: 'fleet-demo',
  balanceCents: 500_000,
  currency: 'COP'
};
