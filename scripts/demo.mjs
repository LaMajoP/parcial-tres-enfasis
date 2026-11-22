import { randomUUID } from 'node:crypto';
const mode = process.argv[2] ?? 'success';
const gateway = process.env.GRAPHQL_URL ?? 'http://localhost:4000/graphql';
async function gql(query, variables = {}) {
  const response = await fetch(gateway, { method: 'POST', headers: { 'content-type': 'application/json', 'x-aegisvolt-role': 'admin-demo', 'x-correlation-id': randomUUID() }, body: JSON.stringify({ query, variables }) });
  const body = await response.json(); if (!response.ok || body.errors) throw new Error(JSON.stringify(body)); return body.data;
}
if (!['success', 'fail-billing', 'fail-charger'].includes(mode)) throw new Error('Modo válido: success, fail-billing o fail-charger.');
const billing = process.env.BILLING_SERVICE_URL ?? 'http://localhost:3002';
const fleetId = `demo-${mode}-${randomUUID()}`;
const balanceCents = mode === 'fail-billing' ? 1 : 500_000;

async function availableConnector() {
  const inventory = await gql('{ stations { stationId connectors { connectorId state } } }');
  for (const station of inventory.stations) {
    const connector = station.connectors.find((item) => item.state === 'AVAILABLE');
    if (connector) return { stationId: station.stationId, connectorId: connector.connectorId };
  }
  throw new Error('No hay conectores AVAILABLE para la demostración. Cierre una sesión local propia o espere su liberación.');
}

const seeded = await fetch(`${billing}/seed`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ fleetId, balanceCents }) });
if (!seeded.ok) throw new Error(`No fue posible crear la billetera efímera de la demo: ${await seeded.text()}`);
const connector = await availableConnector();
if (mode === 'fail-charger') {
  await gql('mutation { setFeatureFlag(name: "SIMULATE_CHARGER_HARDWARE_FAULT", value: true) { name value } }');
}

let saga;
try {
  const result = await gql('mutation Start($input: ReserveAndStartInput!) { reserveAndStartCharging(input: $input) { correlationId error { code message } saga { sagaId state sessionId estimatedCostCents events { type status detail } } } }', { input: { fleetId, ...connector, idempotencyKey: `demo-${mode}-${randomUUID()}` } });
  saga = result.reserveAndStartCharging.saga;
  console.log(JSON.stringify(result, null, 2));
  const events = saga.events.map((event) => event.type);
  if (mode === 'success' && (saga.state !== 'COMPLETED' || !saga.sessionId)) throw new Error(`La demo success debía completar una sesión; obtuvo ${saga.state}.`);
  if (mode === 'fail-billing' && (saga.state !== 'COMPENSATED' || result.reserveAndStartCharging.error?.code !== 'INSUFFICIENT_FUNDS' || !events.includes('RELEASE_SUCCEEDED'))) {
    throw new Error(`La demo fail-billing debía compensar por saldo insuficiente; obtuvo ${saga.state}/${result.reserveAndStartCharging.error?.code ?? 'sin código'}.`);
  }
  if (mode === 'fail-charger' && (saga.state !== 'COMPENSATED' || !events.includes('REFUND_SUCCEEDED') || events.indexOf('REFUND_SUCCEEDED') > events.indexOf('RELEASE_SUCCEEDED'))) {
    throw new Error(`La demo fail-charger debía reembolsar antes de liberar; obtuvo ${saga.state}.`);
  }
  if (mode === 'success' && process.env.KEEP_DEMO_SESSION !== 'true') {
    await gql('mutation Close($id:ID!) { closeCharging(sagaId:$id) { state } }', { id: saga.sagaId });
    console.log('Sesión cerrada para dejar el conector disponible. Use KEEP_DEMO_SESSION=true para conservarla activa.');
  }
} finally {
  if (mode === 'fail-charger') await gql('mutation { setFeatureFlag(name: "SIMULATE_CHARGER_HARDWARE_FAULT", value: false) { name value } }');
}
