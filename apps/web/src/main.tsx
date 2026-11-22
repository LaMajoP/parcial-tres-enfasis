import { StrictMode, useCallback, useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

// Compose inyecta una URL absoluta durante el build. En Kubernetes UI y GraphQL
// comparten ALB privado, por lo que el artefacto promovido usa ruta relativa.
const endpoint = import.meta.env.VITE_GRAPHQL_URL ?? '/graphql';
type Flag = { name: string; value: boolean; environment: string; updatedAt: string; updatedBy: string };
type Saga = { sagaId: string; state: string; sessionId?: string; correlationId: string; estimatedCostCents: number; error?: { code: string; message: string }; events: Array<{ at: string; type: string; status: string; detail?: string }> };
type Telemetry = { timestamp: string; powerKw: number; energyKwh: number; connectorId: string; stationId: string };
type Dashboard = { environment: string; stations: Array<{ stationId: string; connectors: Array<{ connectorId: string; state: string; powerKw: number; isFastCharge: boolean; reservationFleetId?: string }> }>; featureFlags: Flag[]; fleetWallet?: { balanceCents: number; currency: string }; sagaTransactions: Saga[] };
async function graph<T>(query: string, variables: Record<string, unknown> = {}): Promise<T> {
  const response = await fetch(endpoint, { method: 'POST', headers: { 'content-type': 'application/json', 'x-aegisvolt-role': 'admin-demo' }, body: JSON.stringify({ query, variables }) });
  const json = await response.json() as { data?: T; errors?: Array<{ message: string }> };
  if (!response.ok || json.errors?.length || !json.data) throw new Error(json.errors?.map((item) => item.message).join(', ') ?? 'No fue posible consultar AegisVolt.');
  return json.data;
}
const overviewQuery = `query Overview($fleetId: ID!) { environment stations { stationId connectors { connectorId state powerKw isFastCharge reservationFleetId } } featureFlags { name value environment updatedAt updatedBy } fleetWallet(fleetId:$fleetId) { balanceCents currency } sagaTransactions { sagaId state sessionId correlationId estimatedCostCents error { code message } events { at type status detail } } }`;
const money = (cents: number) => new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 }).format(cents / 100);

function App() {
  const [data, setData] = useState<Dashboard>(); const [error, setError] = useState<string>(); const [loading, setLoading] = useState(true);
  const [fleetId, setFleetId] = useState('fleet-demo'); const [stationId, setStationId] = useState('station-bogota-01'); const [connectorId, setConnectorId] = useState('connector-02'); const [fastBoost, setFastBoost] = useState(false); const [submitting, setSubmitting] = useState(false); const [lastSaga, setLastSaga] = useState<Saga>(); const [telemetry, setTelemetry] = useState<Telemetry[]>([]); const [historyFilter, setHistoryFilter] = useState('');
  const reload = useCallback(async () => { try { setError(undefined); const result = await graph<Dashboard>(overviewQuery, { fleetId }); setData(result); } catch (cause) { setError(cause instanceof Error ? cause.message : 'Error desconocido'); } finally { setLoading(false); } }, [fleetId]);
  useEffect(() => { void reload(); const timer = window.setInterval(() => void reload(), 3_000); return () => window.clearInterval(timer); }, [reload]);
  const connectors = useMemo(() => data?.stations.find((station) => station.stationId === stationId)?.connectors ?? [], [data, stationId]);
  useEffect(() => {
    if (!data) return;
    const selected = data.stations.find((station) => station.stationId === stationId)?.connectors.find((connector) => connector.connectorId === connectorId);
    if (selected?.state === 'AVAILABLE') return;
    const available = data.stations.flatMap((station) => station.connectors.filter((connector) => connector.state === 'AVAILABLE').map((connector) => ({ stationId: station.stationId, connectorId: connector.connectorId })))[0];
    if (available) { setStationId(available.stationId); setConnectorId(available.connectorId); }
    else setConnectorId('');
  }, [connectorId, data, stationId]);
  const filteredSagas = useMemo(() => (data?.sagaTransactions ?? []).filter((saga) => `${saga.state} ${saga.sagaId} ${saga.error?.code ?? ''}`.toLowerCase().includes(historyFilter.toLowerCase())), [data, historyFilter]);
  async function submit(event: React.FormEvent) {
    event.preventDefault(); setSubmitting(true); setError(undefined);
    try {
      const idempotencyKey = `ui-${crypto.randomUUID()}`;
      const response = await graph<{ reserveAndStartCharging: { saga: Saga } }>(`mutation Start($input: ReserveAndStartInput!) { reserveAndStartCharging(input:$input) { saga { sagaId state sessionId correlationId estimatedCostCents error { code message } events { at type status detail } } } }`, { input: { fleetId, stationId, connectorId, idempotencyKey, fastChargeBoost: fastBoost } });
      const saga = response.reserveAndStartCharging.saga;
      setLastSaga(saga);
      if (saga.sessionId) {
        const telemetryResponse = await graph<{ telemetry: Telemetry[] }>('query Telemetry($sessionId:ID!) { telemetry(sessionId:$sessionId) { timestamp powerKw energyKwh connectorId stationId } }', { sessionId: saga.sessionId });
        setTelemetry(telemetryResponse.telemetry);
      } else setTelemetry([]);
      await reload();
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible iniciar la carga.'); } finally { setSubmitting(false); }
  }
  async function toggleFlag(flag: Flag) {
    try { await graph(`mutation Flag($name:String!, $value:Boolean!) { setFeatureFlag(name:$name,value:$value) { name value } }`, { name: flag.name, value: !flag.value }); await reload(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible actualizar el flag.'); }
  }
  return <main>
    <header><div><p className="eyebrow">AEGISVOLT / OPERATIONS</p><h1>Control de recarga confiable</h1><p>Disponibilidad, cobro y activación con trazabilidad de SAGA.</p></div><div className="environment" aria-label="Ambiente actual">{data?.environment ?? 'cargando…'}</div></header>
    {error && <div role="alert" className="alert">{error}</div>}
    <section className="metrics" aria-label="Resumen operativo"><article><span>Saldo de la flota</span><strong>{data?.fleetWallet ? money(data.fleetWallet.balanceCents) : '—'}</strong></article><article><span>SAGAs activas</span><strong>{data?.sagaTransactions.filter((saga) => !['COMPLETED', 'COMPENSATED'].includes(saga.state)).length ?? 0}</strong></article><article><span>Actualización</span><strong>cada 3 s</strong></article></section>
    <section><div className="section-title"><div><p className="eyebrow">ELECTROLINERAS</p><h2>Disponibilidad de conectores</h2></div><span className="hint">Polling documentado; no se afirma push instantáneo.</span></div><div className="station-grid">{loading && !data ? <p>Cargando datos operativos…</p> : data?.stations.map((station) => <article className="station" key={station.stationId}><h3>{station.stationId}</h3>{station.connectors.map((connector) => <div className="connector" key={connector.connectorId}><span><b>{connector.connectorId}</b> · {connector.powerKw} kW {connector.isFastCharge ? '⚡' : ''}</span><span className={`state ${connector.state.toLowerCase()}`}>{connector.state}</span></div>)}</article>)}</div></section>
    <section className="two-columns"><form className="panel" onSubmit={submit}><p className="eyebrow">NUEVA SESIÓN</p><h2>Reservar y activar</h2><label>Flota<input value={fleetId} onChange={(event) => setFleetId(event.target.value)} required /></label><label>Estación<select value={stationId} onChange={(event) => { setStationId(event.target.value); setConnectorId(''); }}>{data?.stations.map((station) => <option key={station.stationId} value={station.stationId}>{station.stationId}</option>)}</select></label><label>Conector<select value={connectorId} onChange={(event) => setConnectorId(event.target.value)} required>{connectors.map((connector) => <option key={connector.connectorId} value={connector.connectorId} disabled={connector.state !== 'AVAILABLE'}>{connector.connectorId} · {connector.state}</option>)}</select></label><label className="checkbox"><input type="checkbox" checked={fastBoost} onChange={(event) => setFastBoost(event.target.checked)}/> Solicitar prioridad de ultracarga</label><p className="hint">Estimado: {data?.featureFlags.find((flag) => flag.name === 'ENABLE_DYNAMIC_SURGE_PRICING')?.value ? money(36000) : money(30000)}. El precio surge se calcula en backend.</p><button type="submit" disabled={submitting || !connectorId}>{submitting ? 'Procesando SAGA…' : 'Confirmar reserva y carga'}</button></form>
      <article className="panel"><p className="eyebrow">RESULTADO</p><h2>Progreso de la SAGA</h2>{lastSaga ? <><p><b>{lastSaga.state}</b> · <code>{lastSaga.sagaId}</code></p>{lastSaga.error && <div role="alert" className="alert">{lastSaga.error.code}: {lastSaga.error.message}</div>}<ol className="timeline">{lastSaga.events.map((event, index) => <li key={`${event.at}-${index}`} className={event.status.toLowerCase()}><b>{event.type}</b><small>{event.status} · {new Date(event.at).toLocaleTimeString('es-CO')}</small>{event.detail && <small>{event.detail}</small>}</li>)}</ol></> : <p className="empty">Inicie una sesión para observar cada efecto y compensación durable.</p>}</article></section>
    <section><div className="section-title"><div><p className="eyebrow">FEATURE FLAGS</p><h2>Configuración en caliente</h2></div><span className="hint">Escritura autorizada solo a roles de demostración; producción exige platform-admin.</span></div><div className="flags">{data?.featureFlags.map((flag) => <article key={flag.name} className="flag"><div><b>{flag.name}</b><small>{flag.environment} · {flag.updatedBy}</small></div><button className={flag.value ? 'enabled' : 'disabled'} onClick={() => void toggleFlag(flag)} aria-pressed={flag.value}>{flag.value ? 'ACTIVO' : 'INACTIVO'}</button></article>)}</div></section>
    <section><p className="eyebrow">TELEMETRÍA</p><h2>Sesión seleccionada</h2>{telemetry.length ? <div className="history">{telemetry.map((sample) => <article key={sample.timestamp}><div><b>{sample.powerKw} kW</b><code>{sample.energyKwh} kWh</code></div><span>{sample.connectorId} · {sample.stationId}</span><small>{new Date(sample.timestamp).toLocaleString('es-CO')}</small></article>)}</div> : <p className="empty">Al completar una activación se consultará telemetría durable del dispatch.</p>}</section>
    <section><p className="eyebrow">AUDITORÍA</p><h2>Historial y compensaciones</h2><label>Filtrar por estado, saga o motivo<input value={historyFilter} onChange={(event) => setHistoryFilter(event.target.value)} placeholder="COMPLETED, saga_id, HARDWARE_FAULT…" /></label><div className="history">{filteredSagas.length ? filteredSagas.slice().reverse().map((saga) => <article key={saga.sagaId}><div><b>{saga.state}</b><code>{saga.sagaId}</code></div><span>{money(saga.estimatedCostCents)} · {saga.error?.code ?? 'sin error'}</span><small>correlation_id: {saga.correlationId}</small></article>) : <p className="empty">No hay transacciones que coincidan con el filtro.</p>}</div></section>
  </main>;
}
createRoot(document.getElementById('root')!).render(<StrictMode><App /></StrictMode>);
