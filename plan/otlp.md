# OTLP SDK 實作分析

## 各檔案功能

| 檔案 | 功能 |
|------|------|
| `src/index.ts` | Hono HTTP Server，REST API 路由，連接 MongoDB / PostgreSQL / Redis |
| `src/collector.ts` | 後台定時任務，每 `COLLECT_INTERVAL_MS` ms 將所有裝置的感測值寫入 MongoDB |
| `src/devices.ts` | 靜態裝置清單 (10 台) 與感測屬性定義、隨機值產生器 |
| `src/logger.ts` | Pino logger，結構化 JSON log |
| `src/config.ts` | Zod 驗證 env var，提供型別安全的 `env` 物件 |
| `src/envConfig.ts` | Next.js `loadEnvConfig`，載入 `.env` 檔 |
| `src/seed.ts` | 一次性資料填充，產生約 2M 筆 telemetry 歷史資料 |

---

## 必要前提：新增 `src/instrumentation.ts`

OTel SDK **必須在所有 `import` 之前初始化**，才能讓 auto-instrumentation patch 住 MongoDB / pg / redis driver。

`index.ts` 與 `collector.ts` 的第一行都要改為：

```ts
import "./instrumentation"; // 必須在 ./envConfig 之前
```

---

## Traces

| 位置 | 理由 |
|------|------|
| `src/index.ts:45-53` `GET /api/devices` | 完整 request→mongo 的 span，可看 latency |
| `src/index.ts:64-89` `GET /api/devices/:deviceId/telemetry` | full collection scan（故意無 index），trace 會暴露查詢慢的根因 |
| `src/index.ts:94-109` `GET /api/telemetry/latest` | aggregation on unindexed 2M docs，span duration 會極高 |
| `src/index.ts:119-142` `POST /api/telemetry` | 故意每次 `new MongoClient` 且不 `close()`，trace 會顯示每次多一個 connect span + 無 disconnect，connection leak 的 smoking gun |
| `src/collector.ts:19-37` `setInterval` body | 每個 batch insert 一個 span，可追蹤 collector 頻率、batch size、錯誤率 |

> `@opentelemetry/instrumentation-mongodb`、`instrumentation-pg`、`instrumentation-ioredis` 會自動在 DB call 上建立 child span，手動 span 只需包住業務邏輯層。

---

## Metrics

| 位置 | Metric | 理由 |
|------|--------|------|
| `src/collector.ts:31-35` insert 成功後 | `telemetry.collected.total` (counter) | 觀察 collector 產出速率 |
| `src/collector.ts:34-36` catch 區塊 | `telemetry.collection.errors.total` (counter) | 偵測 MongoDB 寫入失敗 |
| `src/index.ts:124-133` `POST /api/telemetry` | `api.mongo.leaked_connections.total` (counter) | 每次 POST 都 +1，讓 leak 問題在 dashboard 上可視化 |
| `src/index.ts` 全域 middleware | `http.server.request.duration` (histogram) + `http.server.requests.total` (counter) | 所有路由的 latency / throughput / error rate |
| `src/index.ts:29` pgPool | `pg.pool.active` / `pg.pool.idle` / `pg.pool.waiting` (gauge) | 定期讀 `pgPool.totalCount`、`idleCount`、`waitingCount` |

---

## Logs

| 位置 | 做法 | 理由 |
|------|------|------|
| `src/logger.ts` | 加入 `pino-opentelemetry-transport` 或 OTel LogRecord Exporter | 把現有 pino 結構化 log 橋接到 OTLP，不需改任何 `log.info/error` 呼叫 |
| 所有 route handler 的 `log.error` | 加入 `trace_id` / `span_id` 欄位（從 active span 取得） | Log 與 Trace 關聯，Grafana 可以從 log 點進 trace |

---

## 實作優先順序

```
1. src/instrumentation.ts        ← 新建，OTel SDK init + auto-instrumentation
2. src/logger.ts                 ← 加 OTel log bridge（logs 路徑）
3. src/index.ts middleware        ← HTTP metrics + leaked connection counter
4. src/collector.ts setInterval   ← batch insert span + counter
```

最高 ROI 的第一步是 `instrumentation.ts` + auto-instrumentation，幾乎不用改業務邏輯就能拿到所有 DB span。
`POST /api/telemetry` 的 leaked connection counter 是最能直接對應到已知 bug 的 metric，建議一起實作。
