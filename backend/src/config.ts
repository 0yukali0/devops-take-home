import { z } from "zod";

const EnvSchema = z.object({
  MONGO_URI: z.string().default("mongodb://mongo:27017/ems"),
  PG_URI: z
    .string()
    .default("postgresql://postgres:postgres@postgres:5432/ems"),
  REDIS_URL: z.string().default("redis://redis:6379"),
  PORT: z.coerce.number().default(3000),
  COLLECT_INTERVAL_MS: z.coerce.number().default(10_000),
  LOG_LEVEL: z.string().default("info"),
});

export const env = EnvSchema.parse(process.env);
export type Env = z.infer<typeof EnvSchema>;
