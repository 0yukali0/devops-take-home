import "./envConfig";

import { MongoClient } from "mongodb";

import { env } from "./config";
import { DEVICES, generateValue, type Attribute } from "./devices";
import { log } from "./logger";

interface TelemetryDoc {
  deviceId: string;
  attribute: Attribute;
  value: number;
  timestamp: Date;
  ingestedAt: Date;
}

async function seed(): Promise<void> {
  log.info("connecting to mongo");
  const client = new MongoClient(env.MONGO_URI);
  await client.connect();
  const db = client.db();

  log.info("seeding devices");
  await db.collection("devices").deleteMany({});
  await db.collection("devices").insertMany(DEVICES);

  // 30 days of data, one reading per 5 minutes per device per attribute
  // -> ~2M documents total
  log.info("seeding telemetry (this will take a few minutes)");
  await db.collection("telemetry").deleteMany({});

  const now = new Date();
  const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  const batchSize = 10_000;
  let batch: TelemetryDoc[] = [];
  let totalInserted = 0;

  for (const device of DEVICES) {
    for (const attribute of device.attributes) {
      let ts = new Date(thirtyDaysAgo);

      while (ts < now) {
        batch.push({
          deviceId: device.deviceId,
          attribute,
          value: generateValue(attribute),
          timestamp: new Date(ts),
          ingestedAt: new Date(ts.getTime() + Math.random() * 5_000),
        });

        if (batch.length >= batchSize) {
          await db.collection("telemetry").insertMany(batch);
          totalInserted += batch.length;
          batch = [];
          if (totalInserted % 100_000 === 0) {
            log.info({ totalInserted }, "seeding progress");
          }
        }

        ts = new Date(ts.getTime() + 5 * 60 * 1000);
      }
    }
  }

  if (batch.length > 0) {
    await db.collection("telemetry").insertMany(batch);
    totalInserted += batch.length;
  }

  log.info(
    {
      devices: DEVICES.length,
      telemetryDocs: totalInserted,
    },
    "seed complete",
  );
  log.warn("no indexes were created on the telemetry collection");

  await client.close();
}

seed().catch((err) => {
  log.error({ err }, "seed failed");
  process.exit(1);
});
