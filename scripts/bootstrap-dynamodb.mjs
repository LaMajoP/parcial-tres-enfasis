import { CreateTableCommand, DescribeTableCommand, DynamoDBClient, UpdateTimeToLiveCommand } from '@aws-sdk/client-dynamodb';

const endpoint = process.env.DYNAMODB_ENDPOINT ?? 'http://localhost:8000';
const client = new DynamoDBClient({ region: process.env.AWS_REGION ?? 'us-east-1', endpoint, credentials: { accessKeyId: process.env.AWS_ACCESS_KEY_ID ?? 'local', secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY ?? 'local' } });
const domains = ['reservations', 'billing', 'dispatch', 'saga', 'flags'];
const environments = ['dev', 'test', 'prod'];
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitForDynamo() {
  for (let attempt = 1; attempt <= 30; attempt += 1) {
    try { await client.send(new DescribeTableCommand({ TableName: '___not_created___' })); }
    catch (error) { if (error.name === 'ResourceNotFoundException') return; }
    await sleep(1_000);
  }
  throw new Error(`DynamoDB Local no respondió en ${endpoint}`);
}
async function createTable(TableName, domain) {
  try {
    await client.send(new CreateTableCommand({
      TableName, BillingMode: 'PAY_PER_REQUEST',
      AttributeDefinitions: domain === 'saga'
        ? [{ AttributeName: 'PK', AttributeType: 'S' }, { AttributeName: 'SK', AttributeType: 'S' }, { AttributeName: 'GSI1PK', AttributeType: 'S' }, { AttributeName: 'GSI1SK', AttributeType: 'S' }]
        : [{ AttributeName: 'PK', AttributeType: 'S' }, { AttributeName: 'SK', AttributeType: 'S' }],
      KeySchema: [{ AttributeName: 'PK', KeyType: 'HASH' }, { AttributeName: 'SK', KeyType: 'RANGE' }],
      GlobalSecondaryIndexes: domain === 'saga' ? [{ IndexName: 'GSI1', KeySchema: [{ AttributeName: 'GSI1PK', KeyType: 'HASH' }, { AttributeName: 'GSI1SK', KeyType: 'RANGE' }], Projection: { ProjectionType: 'ALL' } }] : undefined
    }));
    console.log(JSON.stringify({ event: 'table_created', TableName }));
  } catch (error) {
    if (error.name !== 'ResourceInUseException') throw error;
    console.log(JSON.stringify({ event: 'table_exists', TableName }));
  }
  if (domain === 'reservations') {
    try { await client.send(new UpdateTimeToLiveCommand({ TableName, TimeToLiveSpecification: { AttributeName: 'expiresAt', Enabled: true } })); } catch (error) { console.warn(JSON.stringify({ event: 'ttl_not_updated', TableName, error: error.name })); }
  }
}
await waitForDynamo();
for (const environment of environments) for (const domain of domains) await createTable(`aegisvolt-${domain}-${environment}`, domain);
