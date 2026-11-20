const [url, timeoutRaw = '60000'] = process.argv.slice(2);
if (!url) throw new Error('Uso: node scripts/wait-for.mjs <url> [timeout_ms]');
const timeoutMs = Number(timeoutRaw);
const started = Date.now();
let lastError = 'sin intento';
while (Date.now() - started < timeoutMs) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(2_000) });
    if (response.ok) {
      console.log(JSON.stringify({ status: 'ready', url, elapsed_ms: Date.now() - started }));
      process.exit(0);
    }
    lastError = `HTTP ${response.status}`;
  } catch (error) { lastError = error instanceof Error ? error.message : String(error); }
  await new Promise((resolve) => setTimeout(resolve, 1_000));
}
throw new Error(`Tiempo agotado esperando ${url}: ${lastError}`);
