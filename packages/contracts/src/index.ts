import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { z } from 'zod';

export { demoConnectors, demoWallet } from './demo-fixtures.js';

export const environments = ['dev', 'test', 'prod'] as const;
export type Environment = (typeof environments)[number];
export const EnvironmentSchema = z.enum(environments);
export const ConnectorStateSchema = z.enum(['AVAILABLE', 'RESERVED', 'CHARGING', 'OUT_OF_SERVICE']);
export type ConnectorState = z.infer<typeof ConnectorStateSchema>;
export const SagaStateSchema = z.enum([
  'PENDING', 'RESERVED', 'CHARGED', 'ACTIVATING', 'COMPLETED', 'COMPENSATING', 'COMPENSATED', 'COMPENSATION_FAILED'
]);
export type SagaState = z.infer<typeof SagaStateSchema>;
const sagaTransitions: Record<SagaState, SagaState[]> = {
  PENDING: ['PENDING', 'RESERVED', 'COMPENSATING', 'COMPENSATED'],
  RESERVED: ['RESERVED', 'CHARGED', 'COMPENSATING', 'COMPENSATED'],
  CHARGED: ['CHARGED', 'ACTIVATING', 'COMPENSATING'],
  ACTIVATING: ['ACTIVATING', 'COMPLETED', 'COMPENSATING'],
  COMPLETED: ['COMPLETED'],
  COMPENSATING: ['COMPENSATING', 'COMPENSATED', 'COMPENSATION_FAILED'],
  COMPENSATED: ['COMPENSATED'],
  COMPENSATION_FAILED: ['COMPENSATION_FAILED', 'COMPENSATING']
};
export const isValidSagaTransition = (from: SagaState, to: SagaState): boolean => sagaTransitions[from].includes(to);
export const DispatchStateSchema = z.enum(['STARTING', 'ACTIVE', 'FAILED', 'STOPPED']);
export type DispatchState = z.infer<typeof DispatchStateSchema>;

export const FlagNames = [
  'ENABLE_DYNAMIC_SURGE_PRICING',
  'ENABLE_FAST_CHARGE_BOOST',
  'SIMULATE_CHARGER_HARDWARE_FAULT'
] as const;
export type FlagName = (typeof FlagNames)[number];
export type FeatureFlags = Record<FlagName, boolean>;
export const defaultFlags = (environment: Environment): FeatureFlags => ({
  ENABLE_DYNAMIC_SURGE_PRICING: environment !== 'prod',
  ENABLE_FAST_CHARGE_BOOST: false,
  SIMULATE_CHARGER_HARDWARE_FAULT: false
});

export const RequestContextSchema = z.object({
  sagaId: z.string().uuid(),
  correlationId: z.string().uuid(),
  idempotencyKey: z.string().min(8).max(128),
  environment: EnvironmentSchema
});
export type RequestContext = z.infer<typeof RequestContextSchema>;

export const ReserveConnectorSchema = RequestContextSchema.extend({
  connectorId: z.string().min(3).max(80),
  stationId: z.string().min(3).max(80),
  fleetId: z.string().min(3).max(80),
  expiresInSeconds: z.number().int().min(30).max(900).default(300),
  requiresFastCharge: z.boolean().default(false)
});
export type ReserveConnectorRequest = z.infer<typeof ReserveConnectorSchema>;

export const DebitWalletSchema = RequestContextSchema.extend({
  fleetId: z.string().min(3).max(80),
  amountCents: z.number().int().positive().max(10_000_000),
  reason: z.string().min(2).max(160)
});
export type DebitWalletRequest = z.infer<typeof DebitWalletSchema>;

export const ActivateChargingSchema = RequestContextSchema.extend({
  stationId: z.string().min(3).max(80),
  connectorId: z.string().min(3).max(80),
  fleetId: z.string().min(3).max(80),
  simulateHardwareFault: z.boolean().default(false),
  simulateTimeout: z.boolean().default(false)
});
export type ActivateChargingRequest = z.infer<typeof ActivateChargingSchema>;

export interface DomainErrorShape {
  code: string;
  message: string;
  retryable: boolean;
  details?: Record<string, string | number | boolean>;
}
export class DomainError extends Error implements DomainErrorShape {
  constructor(
    public code: string,
    message: string,
    public retryable = false,
    public details?: Record<string, string | number | boolean>
  ) { super(message); }
}

export interface Connector {
  connectorId: string;
  stationId: string;
  state: ConnectorState;
  powerKw: number;
  isFastCharge: boolean;
  reservation?: { sagaId: string; fleetId: string; expiresAt: number };
}
export interface Wallet { fleetId: string; balanceCents: number; currency: 'COP'; updatedAt: string; }
export interface Movement { movementId: string; sagaId: string; idempotencyKey: string; amountCents: number; type: 'DEBIT' | 'REFUND'; createdAt: string; reference: string; }
export interface DispatchSession { sessionId: string; sagaId: string; connectorId: string; stationId: string; fleetId: string; state: DispatchState; createdAt: string; }
export interface Telemetry { sessionId: string; connectorId: string; stationId: string; powerKw: number; energyKwh: number; timestamp: string; }
export interface SagaEvent { at: string; type: string; status: 'STARTED' | 'SUCCEEDED' | 'FAILED'; detail?: string; }
export interface SagaTransaction {
  sagaId: string; correlationId: string; idempotencyKey: string; environment: Environment; fleetId: string;
  stationId: string; connectorId: string; estimatedCostCents: number; state: SagaState; error?: DomainErrorShape;
  sessionId?: string; events: SagaEvent[]; createdAt: string; updatedAt: string;
}

export const nowIso = (): string => new Date().toISOString();
export const epochSeconds = (): number => Math.floor(Date.now() / 1000);
export const tableName = (domain: 'reservations' | 'billing' | 'dispatch' | 'saga' | 'flags', environment: Environment): string =>
  process.env[`TABLE_${domain.toUpperCase()}`] ?? `aegisvolt-${domain}-${environment}`;

export const dynamoDocumentClient = (): DynamoDBDocumentClient => {
  const endpoint = process.env.DYNAMODB_ENDPOINT;
  const client = new DynamoDBClient({
    region: process.env.AWS_REGION ?? 'us-east-1',
    endpoint,
    credentials: endpoint ? {
      accessKeyId: process.env.AWS_ACCESS_KEY_ID ?? 'local',
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY ?? 'local'
    } : undefined
  });
  return DynamoDBDocumentClient.from(client, { marshallOptions: { removeUndefinedValues: true } });
};

export const parseEnvironment = (value = process.env.AEGISVOLT_ENV ?? 'dev'): Environment => EnvironmentSchema.parse(value);
export const safeJson = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
