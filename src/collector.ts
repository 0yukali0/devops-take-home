import "./envConfig";

import { MongoClient } from "mongodb";

import { env } from "./config";
import { DEVICES, generateValue } from "./devices";
import { log } from "./logger";

async function collect(): Promise<void> {
  log.info("data collector starting");
  const client = new MongoClient(env.MONGO_URI);
  await client.connect();
  const db = client.db();
  log.info(
    { intervalMs: env.COLLECT_INTERVAL_MS },
    "connected to mongo, beginning collection",
  );

  setInterval(async () => {
    const now = new Date();
    const docs = DEVICES.flatMap((device) =>
      device.attributes.map((attr) => ({
        deviceId: device.deviceId,
        attribute: attr,
        value: generateValue(attr),
        timestamp: now,
        ingestedAt: new Date(),
      })),
    );

    try {
      await db.collection("telemetry").insertMany(docs);
      log.debug({ count: docs.length }, "collected data points");
    } catch (err) {
      log.error({ err }, "collection error");
    }
  }, env.COLLECT_INTERVAL_MS);

  const shutdown = async (): Promise<void> => {
    log.info("shutdown signal received");
    await client.close();
    process.exit(0);
  };

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

collect().catch((err) => {
  log.error({ err }, "collector failed");
  process.exit(1);
});
