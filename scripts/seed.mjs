const gateway = process.env.GRAPHQL_URL ?? 'http://localhost:4000/graphql';
const services = [process.env.STATION_SERVICE_URL ?? 'http://localhost:3001', process.env.BILLING_SERVICE_URL ?? 'http://localhost:3002'];
for (const service of services) {
  const response = await fetch(`${service}/seed`, { method: 'POST', headers: { 'content-type': 'application/json' } });
  if (!response.ok) throw new Error(`No se pudo sembrar ${service}: ${await response.text()}`);
  console.log(await response.text());
}
const response = await fetch(gateway, { method: 'POST', headers: { 'content-type': 'application/json', 'x-aegisvolt-role': 'admin-demo' }, body: JSON.stringify({ query: '{ featureFlags { name value environment } }' }) });
if (!response.ok) throw new Error(await response.text());
console.log(await response.text());
