import "./envConfig";

import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { MongoClient, type Db } from "mongodb";
import pg from "pg";
import { createClient } from "redis";
import { z } from "zod";

import { env } from "./config";
import { log } from "./logger";

// --- MongoDB connection ---
// intentional: no pool size limit, and POST /api/telemetry never releases connections

const mongoClient = new MongoClient(env.MONGO_URI);
let db: Db | undefined;

async function getMongo(): Promise<Db> {
  if (!db) {
    await mongoClient.connect();
    db = mongoClient.db();
  }
  return db;
}

// --- Postgres connection ---

const pgPool = new pg.Pool({ connectionString: env.PG_URI, max: 5 });

// --- Redis connection ---

const redis = createClient({ url: env.REDIS_URL });
redis.on("error", (err) => {
  log.error({ err }, "redis error");
});

// --- Hono app ---

const app = new Hono();

app.get("/health", (c) => c.json({ status: "ok" }));

// Get all devices
app.get("/api/devices", async (c) => {
  try {
    const db = await getMongo();
    const devices = await db.collection("devices").find({}).toArray();
    return c.json(devices);
  } catch (err) {
    log.error({ err }, "GET /api/devices failed");
    return c.json({ error: (err as Error).message }, 500);
  }
});

// Get telemetry for a device
// intentional: queries telemetry without index on deviceId+timestamp — full collection scan
const TelemetryQuerySchema = z.object({
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  limit: z.coerce.number().int().positive().max(10_000).default(100),
});

app.get("/api/devices/:deviceId/telemetry", async (c) => {
  try {
    const db = await getMongo();
    const deviceId = c.req.param("deviceId");
    const { from, to, limit } = TelemetryQuerySchema.parse(c.req.query());

    const filter: Record<string, unknown> = { deviceId };
    if (from || to) {
      const ts: Record<string, Date> = {};
      if (from) ts.$gte = from;
      if (to) ts.$lte = to;
      filter.timestamp = ts;
    }

    const docs = await db
      .collection("telemetry")
      .find(filter)
      .sort({ timestamp: -1 })
      .limit(limit)
      .toArray();

    return c.json(docs);
  } catch (err) {
    log.error({ err }, "GET /api/devices/:deviceId/telemetry failed");
    return c.json({ error: (err as Error).message }, 500);
  }
});

// Get latest telemetry for all devices (dashboard view)
// intentional: aggregation on unindexed collection — very slow with 2M docs
app.get("/api/telemetry/latest", async (c) => {
  try {
    const db = await getMongo();
    const latest = await db
      .collection("telemetry")
      .aggregate([
        { $sort: { timestamp: -1 } },
        { $group: { _id: "$deviceId", latest: { $first: "$$ROOT" } } },
      ])
      .toArray();
    return c.json(latest.map((d) => d.latest));
  } catch (err) {
    log.error({ err }, "GET /api/telemetry/latest failed");
    return c.json({ error: (err as Error).message }, 500);
  }
});

// Ingest telemetry data point
const IngestSchema = z.object({
  deviceId: z.string(),
  attribute: z.string(),
  value: z.number(),
  timestamp: z.coerce.date().optional(),
});

app.post("/api/telemetry", async (c) => {
  try {
    const body = IngestSchema.parse(await c.req.json());

    // intentional: opens a fresh MongoClient per request and never closes it
    const insertClient = new MongoClient(env.MONGO_URI);
    await insertClient.connect();
    const insertDb = insertClient.db();

    await insertDb.collection("telemetry").insertOne({
      deviceId: body.deviceId,
      attribute: body.attribute,
      value: body.value,
      timestamp: body.timestamp ?? new Date(),
      ingestedAt: new Date(),
    });

    // intentional: insertClient.close() is never called — leaks
    return c.json({ status: "ok" });
  } catch (err) {
    log.error({ err }, "POST /api/telemetry failed");
    return c.json({ error: (err as Error).message }, 500);
  }
});

// Postgres: dashboard configs
app.get("/api/dashboards", async (c) => {
  try {
    const result = await pgPool.query(
      "SELECT * FROM dashboards ORDER BY created_at DESC",
    );
    return c.json(result.rows);
  } catch (err) {
    log.error({ err }, "GET /api/dashboards failed");
    return c.json({ error: (err as Error).message }, 500);
  }
});

const DashboardCreateSchema = z.object({
  name: z.string().min(1),
  config: z.record(z.unknown()),
});

app.post("/api/dashboards", async (c) => {
  try {
    const body = DashboardCreateSchema.parse(await c.req.json());
    const result = await pgPool.query(
      "INSERT INTO dashboards (name, config) VALUES ($1, $2) RETURNING *",
      [body.name, JSON.stringify(body.config)],
    );
    return c.json(result.rows[0]);
  } catch (err) {
    log.error({ err }, "POST /api/dashboards failed");
    return c.json({ error: (err as Error).message }, 500);
  }
});

// Redis cache
app.get("/api/cache/:key", async (c) => {
  try {
    const key = c.req.param("key");
    const val = await redis.get(key);
    return c.json({ key, value: val ? JSON.parse(val) : null });
  } catch (err) {
    log.error({ err }, "GET /api/cache/:key failed");
    return c.json({ error: (err as Error).message }, 500);
  }
});

// --- Startup ---

async function start(): Promise<void> {
  try {
    await redis.connect();
    log.info("connected to redis");
  } catch (err) {
    log.error({ err }, "redis connect failed");
  }

  try {
    await pgPool.query(`
      CREATE TABLE IF NOT EXISTS dashboards (
        id SERIAL PRIMARY KEY,
        name TEXT NOT NULL,
        config JSONB NOT NULL DEFAULT '{}',
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    log.info("postgres tables initialized");
  } catch (err) {
    log.error({ err }, "postgres init failed");
  }

  const server = serve({
    fetch: app.fetch,
    port: env.PORT,
  });

  log.info({ port: env.PORT }, "ems-edge api listening");

  const shutdown = (): void => {
    log.info("shutdown signal received");
    server.close();
  };

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

start().catch((err) => {
  log.error({ err }, "fatal startup error");
  process.exit(1);
});
