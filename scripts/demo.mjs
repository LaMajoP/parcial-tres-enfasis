import { randomUUID } from 'node:crypto';
const mode = process.argv[2] ?? 'success';
const gateway = process.env.GRAPHQL_URL ?? 'http://localhost:4000/graphql';
async function gql(query, variables = {}) {
  const response = await fetch(gateway, { method: 'POST', headers: { 'content-type': 'application/json', 'x-aegisvolt-role': 'admin-demo', 'x-correlation-id': randomUUID() }, body: JSON.stringify({ query, variables }) });
  const body = await response.json(); if (!response.ok || body.errors) throw new Error(JSON.stringify(body)); return body.data;
}
if (mode === 'fail-charger') await gql('mutation { setFeatureFlag(name: "SIMULATE_CHARGER_HARDWARE_FAULT", value: true) { name value } }');
let fleetId = 'fleet-demo'; let stationId = 'station-bogota-01'; let connectorId = mode === 'fail-charger' ? 'connector-01' : 'connector-02';
if (mode === 'fail-billing') {
  const billing = process.env.BILLING_SERVICE_URL ?? 'http://localhost:3002';
  const seeded = await fetch(`${billing}/seed`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ fleetId: 'fleet-demo-insufficient', balanceCents: 1 }) });
  if (!seeded.ok) throw new Error(`No fue posible sembrar billetera insuficiente: ${await seeded.text()}`);
  fleetId = 'fleet-demo-insufficient'; stationId = 'station-chia-01'; connectorId = 'connector-04';
}
const result = await gql('mutation Start($input: ReserveAndStartInput!) { reserveAndStartCharging(input: $input) { correlationId error { code message } saga { sagaId state sessionId estimatedCostCents events { type status detail } } } }', { input: { fleetId, stationId, connectorId, idempotencyKey: `demo-${mode}-${randomUUID()}` } });
console.log(JSON.stringify(result, null, 2));
