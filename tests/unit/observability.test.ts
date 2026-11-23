import { afterEach, describe, expect, it, vi } from 'vitest';
import { correlationIdFrom, log } from '@aegisvolt/shared-observability';

describe('logs estructurados de AegisVolt', () => {
  afterEach(() => vi.restoreAllMocks());

  it('emite timestamp, nivel, evento, servicio, ambiente y correlation_id como JSON', () => {
    const output = vi.spyOn(console, 'log').mockImplementation(() => undefined);
    log({
      service: 'billing-wallet-service', environment: 'test', operation: 'refund_wallet',
      status: 'SUCCEEDED', correlation_id: 'corr-test-123', saga_id: 'saga-test-123'
    });
    const record = JSON.parse(String(output.mock.calls[0][0]));
    expect(Number.isNaN(Date.parse(record.timestamp))).toBe(false);
    expect(record.level).toBe('INFO');
    expect(record.event).toBe('refund_wallet');
    expect(record.service).toBe('billing-wallet-service');
    expect(record.service_group).toBe('billing-wallet');
    expect(record.environment).toBe('test');
    expect(record.correlation_id).toBe('corr-test-123');
  });

  it('propaga x-correlation-id y genera uno si falta', () => {
    expect(correlationIdFrom({ 'x-correlation-id': 'saga-corr' })).toBe('saga-corr');
    expect(correlationIdFrom({})).toMatch(/^[0-9a-f-]{36}$/i);
  });

  it('mantiene saneamiento de secretos dentro de eventos JSON', () => {
    const output = vi.spyOn(console, 'log').mockImplementation(() => undefined);
    log({
      service: 'graphql-gateway', environment: 'dev', operation: 'reserve', status: 'FAILED',
      correlation_id: 'corr-safe', authorization: 'Bearer never-log-this'
    });
    const serialized = String(output.mock.calls[0][0]);
    expect(serialized).not.toContain('never-log-this');
    expect(JSON.parse(serialized).correlation_id).toBe('corr-safe');
  });
});
