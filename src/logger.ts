import pino from "pino";

export const rootLogger = pino({
  level: process.env.LOG_LEVEL ?? "info",
});

export const log = rootLogger.child({
  module: "ems-edge",
});
