import { MongoClient } from 'mongodb';

const BATCH_SIZE = 1000;

async function run(mongoUri: string): Promise<void> {
  const client = new MongoClient(mongoUri);
  try {
    await client.connect();
    const col = client.db().collection('telemetry');

    await col.createIndex(
      { deviceId: 1, timestamp: -1 },
      { name: 'deviceId_timestamp_idx' }
    );
    console.log('Index ready: deviceId_timestamp_idx');

    let total = 0;
    while (true) {
      const batch = await col
        .find({ newField: { $exists: false } }, { projection: { _id: 1 } })
        .limit(BATCH_SIZE)
        .toArray();
      if (batch.length === 0) break;
      const ids = batch.map(d => d._id);
      const result = await col.updateMany(
        { _id: { $in: ids } },
        { $set: { newField: null } }
      );
      total += result.modifiedCount;
    }
    console.log(`Backfill complete: ${total} documents updated`);
  } catch (err) {
    const error = err instanceof Error ? err : new Error(String(err));
    process.stderr.write(`Migration failed: ${error.message}\n${error.stack ?? ''}\n`);
    process.exit(1);
  } finally {
    await client.close();
  }
}

const MONGO_URI = process.env['MONGO_URI'];
if (!MONGO_URI) {
  process.stderr.write('MONGO_URI is required\n');
  process.exit(1);
}

run(MONGO_URI);
