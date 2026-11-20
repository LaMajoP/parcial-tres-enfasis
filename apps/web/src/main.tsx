import { StrictMode, useCallback, useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

const endpoint = import.meta.env.VITE_GRAPHQL_URL ?? 'http://localhost:4000/graphql';
type Flag = { name: string; value: boolean; environment: string; updatedAt: string; updatedBy: string };
type Saga = { sagaId: string; state: string; sessionId?: string; correlationId: string; estimatedCostCents: number; error?: { code: string; message: string }; events: Array<{ at: string; type: string; status: string; detail?: string }> };
type Dashboard = { environment: string; stations: Array<{ stationId: string; connectors: Array<{ connectorId: string; state: string; powerKw: number; isFastCharge: boolean; reservationFleetId?: string }> }>; featureFlags: Flag[]; fleetWallet?: { balanceCents: number; currency: string }; sagaTransactions: Saga[] };
async function graph<T>(query: string, variables: Record<string, unknown> = {}): Promise<T> {
  const response = await fetch(endpoint, { method: 'POST', headers: { 'content-type': 'application/json', 'x-aegisvolt-role': 'admin-demo' }, body: JSON.stringify({ query, variables }) });
  const json = await response.json() as { data?: T; errors?: Array<{ message: string }> };
  if (!response.ok || json.errors?.length || !json.data) throw new Error(json.errors?.map((item) => item.message).join(', ') ?? 'No fue posible consultar AegisVolt.');
  return json.data;
}
const overviewQuery = `query Overview { environment stations { stationId connectors { connectorId state powerKw isFastCharge reservationFleetId } } featureFlags { name value environment updatedAt updatedBy } fleetWallet(fleetId:"fleet-demo") { balanceCents currency } sagaTransactions { sagaId state sessionId correlationId estimatedCostCents error { code message } events { at type status detail } } }`;
const money = (cents: number) => new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 }).format(cents / 100);

function App() {
  const [data, setData] = useState<Dashboard>(); const [error, setError] = useState<string>(); const [loading, setLoading] = useState(true);
  const [stationId, setStationId] = useState('station-bogota-01'); const [connectorId, setConnectorId] = useState('connector-02'); const [fastBoost, setFastBoost] = useState(false); const [submitting, setSubmitting] = useState(false); const [lastSaga, setLastSaga] = useState<Saga>();
  const reload = useCallback(async () => { try { setError(undefined); const result = await graph<Dashboard>(overviewQuery); setData(result); } catch (cause) { setError(cause instanceof Error ? cause.message : 'Error desconocido'); } finally { setLoading(false); } }, []);
  useEffect(() => { void reload(); const timer = window.setInterval(() => void reload(), 3_000); return () => window.clearInterval(timer); }, [reload]);
  const connectors = useMemo(() => data?.stations.find((station) => station.stationId === stationId)?.connectors ?? [], [data, stationId]);
  async function submit(event: React.FormEvent) {
    event.preventDefault(); setSubmitting(true); setError(undefined);
    try {
      const idempotencyKey = `ui-${crypto.randomUUID()}`;
      const response = await graph<{ reserveAndStartCharging: { saga: Saga } }>(`mutation Start($input: ReserveAndStartInput!) { reserveAndStartCharging(input:$input) { saga { sagaId state sessionId correlationId estimatedCostCents error { code message } events { at type status detail } } } }`, { input: { fleetId: 'fleet-demo', stationId, connectorId, idempotencyKey, fastChargeBoost: fastBoost } });
      setLastSaga(response.reserveAndStartCharging.saga); await reload();
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible iniciar la carga.'); } finally { setSubmitting(false); }
  }
  async function toggleFlag(flag: Flag) {
    try { await graph(`mutation Flag($name:String!, $value:Boolean!) { setFeatureFlag(name:$name,value:$value) { name value } }`, { name: flag.name, value: !flag.value }); await reload(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible actualizar el flag.'); }
  }
  return <main>
    <header><div><p className="eyebrow">AEGISVOLT / OPERATIONS</p><h1>Control de recarga confiable</h1><p>Disponibilidad, cobro y activación con trazabilidad de SAGA.</p></div><div className="environment" aria-label="Ambiente actual">{data?.environment ?? 'cargando…'}</div></header>
    {error && <div role="alert" className="alert">{error}</div>}
    <section className="metrics" aria-label="Resumen operativo"><article><span>Saldo Fleet Demo</span><strong>{data?.fleetWallet ? money(data.fleetWallet.balanceCents) : '—'}</strong></article><article><span>SAGAs activas</span><strong>{data?.sagaTransactions.filter((saga) => !['COMPLETED', 'COMPENSATED'].includes(saga.state)).length ?? 0}</strong></article><article><span>Actualización</span><strong>cada 3 s</strong></article></section>
    <section><div className="section-title"><div><p className="eyebrow">ELECTROLINERAS</p><h2>Disponibilidad de conectores</h2></div><span className="hint">Polling documentado; no se afirma push instantáneo.</span></div><div className="station-grid">{loading && !data ? <p>Cargando datos operativos…</p> : data?.stations.map((station) => <article className="station" key={station.stationId}><h3>{station.stationId}</h3>{station.connectors.map((connector) => <div className="connector" key={connector.connectorId}><span><b>{connector.connectorId}</b> · {connector.powerKw} kW {connector.isFastCharge ? '⚡' : ''}</span><span className={`state ${connector.state.toLowerCase()}`}>{connector.state}</span></div>)}</article>)}</div></section>
    <section className="two-columns"><form className="panel" onSubmit={submit}><p className="eyebrow">NUEVA SESIÓN</p><h2>Reservar y activar</h2><label>Estación<select value={stationId} onChange={(event) => { setStationId(event.target.value); setConnectorId(''); }}>{data?.stations.map((station) => <option key={station.stationId} value={station.stationId}>{station.stationId}</option>)}</select></label><label>Conector<select value={connectorId} onChange={(event) => setConnectorId(event.target.value)} required>{connectors.map((connector) => <option key={connector.connectorId} value={connector.connectorId} disabled={connector.state !== 'AVAILABLE'}>{connector.connectorId} · {connector.state}</option>)}</select></label><label className="checkbox"><input type="checkbox" checked={fastBoost} onChange={(event) => setFastBoost(event.target.checked)}/> Solicitar prioridad de ultracarga</label><p className="hint">Estimado: {data?.featureFlags.find((flag) => flag.name === 'ENABLE_DYNAMIC_SURGE_PRICING')?.value ? money(36000) : money(30000)}. El precio surge se calcula en backend.</p><button disabled={submitting || !connectorId}>{submitting ? 'Procesando SAGA…' : 'Confirmar reserva y carga'}</button></form>
      <article className="panel"><p className="eyebrow">RESULTADO</p><h2>Progreso de la SAGA</h2>{lastSaga ? <><p><b>{lastSaga.state}</b> · <code>{lastSaga.sagaId}</code></p>{lastSaga.error && <div role="alert" className="alert">{lastSaga.error.code}: {lastSaga.error.message}</div>}<ol className="timeline">{lastSaga.events.map((event, index) => <li key={`${event.at}-${index}`} className={event.status.toLowerCase()}><b>{event.type}</b><small>{event.status} · {new Date(event.at).toLocaleTimeString('es-CO')}</small>{event.detail && <small>{event.detail}</small>}</li>)}</ol></> : <p className="empty">Inicie una sesión para observar cada efecto y compensación durable.</p>}</article></section>
    <section><div className="section-title"><div><p className="eyebrow">FEATURE FLAGS</p><h2>Configuración en caliente</h2></div><span className="hint">Escritura autorizada solo a roles de demostración; producción exige platform-admin.</span></div><div className="flags">{data?.featureFlags.map((flag) => <article key={flag.name} className="flag"><div><b>{flag.name}</b><small>{flag.environment} · {flag.updatedBy}</small></div><button className={flag.value ? 'enabled' : 'disabled'} onClick={() => void toggleFlag(flag)} aria-pressed={flag.value}>{flag.value ? 'ACTIVO' : 'INACTIVO'}</button></article>)}</div></section>
    <section><p className="eyebrow">AUDITORÍA</p><h2>Historial y compensaciones</h2><div className="history">{data?.sagaTransactions.length ? data.sagaTransactions.slice().reverse().map((saga) => <article key={saga.sagaId}><div><b>{saga.state}</b><code>{saga.sagaId}</code></div><span>{money(saga.estimatedCostCents)} · {saga.error?.code ?? 'sin error'}</span><small>correlation_id: {saga.correlationId}</small></article>) : <p className="empty">Aún no hay transacciones.</p>}</div></section>
  </main>;
}
createRoot(document.getElementById('root')!).render(<StrictMode><App /></StrictMode>);
