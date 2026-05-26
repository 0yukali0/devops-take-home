# EMS Edge Backend

能源管理系統（Energy Management System）後端服務，負責裝置遙測資料的收集、儲存與查詢。

---

## 專案結構

```
backend/
├── src/
│   ├── index.ts          # HTTP API 伺服器進入點
│   ├── collector.ts      # 遙測資料收集排程服務
│   ├── seed.ts           # 開發用資料初始化腳本
│   ├── devices.ts        # 裝置定義與資料產生邏輯
│   ├── config.ts         # 環境變數 schema (zod)
│   ├── envConfig.ts      # dotenv 載入
│   └── logger.ts         # pino logger 設定
├── migrate/
│   └── index.ts          # 資料庫 migration 腳本
├── traefik/
│   ├── traefik.yml       # Traefik 靜態設定
│   └── dynamic/          # Traefik 動態路由設定（藍綠部署時切換）
├── Dockerfile            # 多階段建置映像
├── docker-compose.yaml   # 本地開發環境
├── deploy.sh             # 藍綠部署腳本
└── Makefile              # 常用指令封裝
```

### 服務架構

```mermaid
graph TB
    subgraph Docker Compose
        Traefik["Traefik\n(Reverse Proxy :80)"]
        App["app\n(Hono API :3000)"]
        Collector["collector\n(排程收集器)"]
        Mongo["MongoDB :27017"]
        Postgres["PostgreSQL :5432"]
        Redis["Redis :6379"]
    end

    Client["HTTP Client"] -->|":80"| Traefik
    Traefik -->|proxy| App
    App -->|devices / telemetry| Mongo
    App -->|dashboards| Postgres
    App -->|cache| Redis
    Collector -->|insertMany telemetry| Mongo
```

---

## 功能

### API 端點

```mermaid
graph LR
    API["Hono API"]

    API --> H["GET /health"]
    API --> GD["GET /api/devices"]
    API --> GT["GET /api/devices/:deviceId/telemetry\n?from&to&limit"]
    API --> GL["GET /api/telemetry/latest"]
    API --> PT["POST /api/telemetry"]
    API --> GDB["GET /api/dashboards"]
    API --> PDB["POST /api/dashboards"]
    API --> GC["GET /api/cache/:key"]
```

| 端點 | 說明 | 資料庫 |
|------|------|--------|
| `GET /health` | 健康檢查 | — |
| `GET /api/devices` | 取得所有裝置清單 | MongoDB |
| `GET /api/devices/:id/telemetry` | 取得指定裝置的遙測資料（支援時間範圍篩選） | MongoDB |
| `GET /api/telemetry/latest` | 取得每台裝置最新一筆遙測 | MongoDB |
| `POST /api/telemetry` | 寫入一筆遙測資料 | MongoDB |
| `GET /api/dashboards` | 取得儀表板設定列表 | PostgreSQL |
| `POST /api/dashboards` | 建立儀表板設定 | PostgreSQL |
| `GET /api/cache/:key` | 讀取 Redis 快取值 | Redis |

### 裝置與遙測資料模型

```mermaid
erDiagram
    DEVICE {
        string deviceId PK
        string type
        string site
        array  attributes
    }
    TELEMETRY {
        ObjectId _id PK
        string deviceId FK
        string attribute
        float  value
        date   timestamp
        date   ingestedAt
    }
    DASHBOARD {
        serial id PK
        string name
        jsonb  config
        timestamp created_at
    }

    DEVICE ||--o{ TELEMETRY : "has"
```

裝置類型：`inverter`、`battery`、`meter`、`solar`、`hvac`

量測屬性：`power`、`voltage`、`current`、`frequency`、`soc`、`temperature`、`energy`、`irradiance`、`flow_rate`

### 資料收集流程

```mermaid
sequenceDiagram
    participant C as Collector
    participant M as MongoDB

    loop 每 COLLECT_INTERVAL_MS（預設 10s）
        C->>C: 對所有裝置的所有屬性產生隨機值
        C->>M: insertMany(telemetry docs)
    end
```

### 藍綠部署流程

```mermaid
flowchart TD
    A["make deploy VERSION=v2\n./deploy.sh backend:v2"] --> B["驗證 image 存在"]
    B --> C["執行 migrate/index.ts\n（建立索引、backfill newField）"]
    C -->|失敗| ABORT["中止部署"]
    C -->|成功| D["啟動 green 容器 app-new:3001"]
    D --> E{"Health Check\nGET /health\n(60s timeout)"}
    E -->|失敗| ROLLBACK["停止 app-new\n回滾"]
    E -->|成功| F["更新 Traefik dynamic config\n→ 指向 app-new:3000"]
    F --> G["停止並移除 blue 容器 app"]
    G --> H["還原 Traefik config\n→ 指向 app:3000"]
    H --> I["docker rename app-new → app"]
    I --> J["部署完成"]
```

---

## 如何開發

### 前置需求

- Docker & Docker Compose
- Node.js 22+、pnpm 9

### 本地啟動

```bash
# 建置映像並啟動所有服務（含資料 seed）
make dev-start

# 停止所有服務
make dev-stop
```

`dev-start` 會依序執行：
1. 建置 Docker image（`backend:dev`）
2. `docker compose up -d`（啟動 Traefik、app、collector、MongoDB、PostgreSQL、Redis）
3. 執行 `seed.ts` 寫入 10 台裝置定義及約 200 萬筆 30 天歷史遙測資料

### 環境變數

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `MONGO_URI` | `mongodb://mongo:27017/ems` | MongoDB 連線字串 |
| `PG_URI` | `postgresql://postgres:postgres@postgres:5432/ems` | PostgreSQL 連線字串 |
| `REDIS_URL` | `redis://redis:6379` | Redis 連線字串 |
| `PORT` | `3000` | API 伺服器埠號 |
| `COLLECT_INTERVAL_MS` | `10000` | 收集器間隔（毫秒） |
| `LOG_LEVEL` | `info` | pino log 等級 |

### 建置流程

```mermaid
flowchart LR
    A["src/\nmigrate/"] -->|"pnpm build\n(tsc + esbuild)"| B["dist/\n├── index.js\n├── collector.js\n├── seed.js\n└── migrate/index.js"]
    B -->|"Docker multi-stage"| C["production image\n(node:22-alpine)"]
```

### 常用指令

```bash
# 建置 image
make image VERSION=v1

# 執行 lint
make lint

# 執行資料庫 migration
make migrate VERSION=v1

# 整合測試：migration + 藍綠部署端對端驗證
make migration-test
```

### Migration

`migrate/index.ts` 執行兩件事：

1. 在 `telemetry` collection 建立複合索引 `{ deviceId: 1, timestamp: -1 }`
2. 批次 backfill 舊文件，補齊 `newField: null`（冪等，可安全重複執行）
