import { randomUUID } from 'node:crypto';
import type { Environment } from '@aegisvolt/contracts';

export interface LogFields {
  level?: 'INFO' | 'WARN' | 'ERROR'; service: string; environment: Environment; operation: string;
  status: 'STARTED' | 'SUCCEEDED' | 'FAILED'; correlation_id?: string; saga_id?: string;
  duration_ms?: number; error_code?: string; [key: string]: unknown;
}

const sanitize = (value: unknown): unknown => {
  if (Array.isArray(value)) return value.map(sanitize);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value as Record<string, unknown>)
    .filter(([key]) => !/token|secret|authorization|password|balance/i.test(key))
    .map(([key, child]) => [key, sanitize(child)]));
  return value;
};

export const log = (fields: LogFields): void => {
  console.log(JSON.stringify(sanitize({ timestamp: new Date().toISOString(), level: 'INFO', ...fields })));
};

export const correlationIdFrom = (headers: Record<string, string | string[] | undefined>): string => {
  const value = headers['x-correlation-id'];
  return typeof value === 'string' && value.length > 0 ? value : randomUUID();
};

export class Metrics {
  private readonly counters = new Map<string, number>();
  constructor(
    private readonly service: string,
    private readonly environment: Environment,
    private readonly namespace = 'AegisVolt/Service'
  ) {}
  private emit(name: string, value: number, unit: 'Count' | 'Milliseconds'): void {
    const timestamp = Date.now();
    // CloudWatch Embedded Metric Format: Fluent Bit reenvía esta línea JSON sin transformarla.
    console.log(JSON.stringify({
      timestamp: new Date(timestamp).toISOString(), level: 'INFO', service: this.service, environment: this.environment,
      operation: 'metric', status: 'SUCCEEDED', [name]: value,
      _aws: { Timestamp: timestamp, CloudWatchMetrics: [{ Namespace: this.namespace, Dimensions: [['Environment', 'Service']], Metrics: [{ Name: name, Unit: unit }] }] }
    }));
  }
  increment(name: string): void {
    const count = (this.counters.get(name) ?? 0) + 1;
    this.counters.set(name, count);
    this.emit(name, 1, 'Count');
  }
  observe(name: string, value: number): void { this.emit(name, value, 'Milliseconds'); }
  prometheus(): string { return [...this.counters.entries()].map(([name, count]) => `aegisvolt_${name} ${count}`).join('\n'); }
}
