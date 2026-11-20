const gateway = process.env.GRAPHQL_URL ?? 'http://localhost:4000/graphql';
const services = [process.env.STATION_SERVICE_URL ?? 'http://localhost:3001', process.env.BILLING_SERVICE_URL ?? 'http://localhost:3002'];
const readyUrls = [...services.map((service) => `${service}/health/ready`), `${gateway.replace(/\/graphql$/, '')}/health/ready`];
for (const url of readyUrls) {
  // El proceso principal usa fetch y falla explícitamente tras 60 s; no confía en depends_on.
  const started = Date.now(); let lastError = 'sin intento';
  while (Date.now() - started < 60_000) {
    try { const response = await fetch(url, { signal: AbortSignal.timeout(2_000) }); if (response.ok) break; lastError = `HTTP ${response.status}`; }
    catch (error) { lastError = error instanceof Error ? error.message : String(error); }
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  if (Date.now() - started >= 60_000) throw new Error(`Tiempo agotado esperando ${url}: ${lastError}`);
}
for (const service of services) {
  const response = await fetch(`${service}/seed`, { method: 'POST', headers: { 'content-type': 'application/json' } });
  if (!response.ok) throw new Error(`No se pudo sembrar ${service}: ${await response.text()}`);
  console.log(await response.text());
}
const response = await fetch(gateway, { method: 'POST', headers: { 'content-type': 'application/json', 'x-aegisvolt-role': 'admin-demo' }, body: JSON.stringify({ query: '{ featureFlags { name value environment } }' }) });
if (!response.ok) throw new Error(await response.text());
console.log(await response.text());
