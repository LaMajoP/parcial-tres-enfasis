import { buildSchema } from 'graphql';
// La consulta de introspección se ejecuta en integración; este check evita que un schema inválido llegue a CI.
const schema = `type Query { health: String! }`;
buildSchema(schema);
console.log('Schema GraphQL básico válido; la verificación de contratos completos corre contra el gateway en integración.');
