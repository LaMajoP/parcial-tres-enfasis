import { describe, expect, it } from 'vitest';
import { defaultFlags, isValidSagaTransition, tableName } from '@aegisvolt/contracts';

describe('reglas de dominio compartidas', () => {
  it('aplica surge en dev/test pero no en prod', () => {
    expect(defaultFlags('dev').ENABLE_DYNAMIC_SURGE_PRICING).toBe(true);
    expect(defaultFlags('test').ENABLE_DYNAMIC_SURGE_PRICING).toBe(true);
    expect(defaultFlags('prod').ENABLE_DYNAMIC_SURGE_PRICING).toBe(false);
  });
  it('solo permite transiciones de SAGA recuperables y terminales correctas', () => {
    expect(isValidSagaTransition('RESERVED', 'CHARGED')).toBe(true);
    expect(isValidSagaTransition('ACTIVATING', 'COMPENSATING')).toBe(true);
    expect(isValidSagaTransition('COMPLETED', 'COMPENSATING')).toBe(false);
    expect(isValidSagaTransition('PENDING', 'COMPLETED')).toBe(false);
  });
  it('aísla tablas de flags y dominio por ambiente', () => {
    expect(tableName('flags', 'dev')).not.toEqual(tableName('flags', 'prod'));
    expect(tableName('billing', 'test')).toBe('aegisvolt-billing-test');
  });
});
