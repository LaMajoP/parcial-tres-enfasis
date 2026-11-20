import { readFileSync } from 'node:fs';
import { buildSchema, validateSchema } from 'graphql';

// Lee el SDL que entrega el gateway; no valida un schema de juguete.
const source = readFileSync('apps/graphql-gateway/src/index.ts', 'utf8');
const match = source.match(/const typeDefs\s*=\s*\/\* GraphQL \*\/\s*`([\s\S]*?)`;/);
if (!match) throw new Error('No se pudo localizar typeDefs en el gateway GraphQL.');
const schema = buildSchema(match[1]);
const errors = validateSchema(schema);
if (errors.length > 0) throw new Error(errors.map((error) => error.message).join('\n'));

const queryFields = Object.keys(schema.getQueryType()?.getFields() ?? {});
const mutationFields = Object.keys(schema.getMutationType()?.getFields() ?? {});
for (const field of ['stations', 'station', 'connectorAvailability', 'telemetry', 'fleetWallet', 'sagaTransactions', 'sagaTransaction', 'featureFlags', 'environment']) {
  if (!queryFields.includes(field)) throw new Error(`Falta Query.${field} en el contrato GraphQL.`);
}
for (const field of ['reserveAndStartCharging', 'closeCharging', 'setFeatureFlag', 'reconcileSagas']) {
  if (!mutationFields.includes(field)) throw new Error(`Falta Mutation.${field} en el contrato GraphQL.`);
}
console.log('Schema GraphQL del gateway válido y con los contratos obligatorios.');
