# Ticket 1 — Database Misconfiguration: Requirements

## 背景資料分析

### MongoDB 資料量估算（現行 stack）

**設備與 attribute 數量：**

| 設備 | 類型 | Attributes | 數量 |
|------|------|-----------|------|
| inverter-01, 02 | inverter | power, voltage, current, frequency | 4 × 2 = 8 |
| bess-01, 02 | battery | soc, power, voltage, temperature | 4 × 2 = 8 |
| meter-main-01, 02 | meter | power, energy, voltage, current | 4 × 2 = 8 |
| meter-sub-01 | meter | power, energy | 2 |
| solar-01, 02 | solar | power, irradiance, temperature | 3 × 2 = 6 |
| chiller-01 | hvac | power, temperature, flow_rate | 3 |
| **合計** | | | **35 docs/cycle** |

**Collector 寫入頻率：** 每 10 秒 1 cycle → 每天 8,640 次  
**每天寫入量：** 8,640 × 35 = **302,400 docs/day ≈ 300K docs/day**

**每筆文件大小估算（BSON）：**

| 欄位 | 型別 | 大小 |
|------|------|------|
| `_id` | ObjectId | 12 bytes |
| `deviceId` | string ≈ 15 chars | ~17 bytes |
| `attribute` | string ≈ 10 chars | ~12 bytes |
| `value` | double | 8 bytes |
| `timestamp` | Date | 8 bytes |
| `ingestedAt` | Date | 8 bytes |
| BSON 欄位名稱 + header 開銷 | | ~50 bytes |
| **合計** | | **~115 bytes/doc** |

WiredTiger 預設壓縮（snappy）約壓縮 40–60%，實際磁碟佔用 **~60–70 bytes/doc**。

**月資料量：**

| 指標 | 數值 |
|------|------|
| 文件數/月 | 302,400 × 30 = **~9.1M docs** |
| 原始資料大小/月 | 9.1M × 115 bytes ≈ **~1.05 GB** |
| 壓縮後磁碟/月 | **~500–650 MB/month** |
| 加上 index（無 index 則 0）| 若加 compound index (deviceId, timestamp)：+~150 MB |

> **注意：** 現行 seed.ts 以 5 分鐘間隔回填 30 天歷史資料（約 ~300K docs），
> 但 collector 正式運行是 **10 秒**間隔，月成長速度遠高於 seed 的基準。

---

### PostgreSQL 資料量估算

**目前 schema（動態建立）：**

```sql
CREATE TABLE dashboards (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  config JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
)
```

- 靜態設定資料，增長緩慢
- 每筆 dashboard row 估約 1–5 KB（JSONB config）
- 初始大小：< 10 MB；一年後預估 < 100 MB
- **不是成長瓶頸**，但 `shared_buffers = 128MB` 仍偏低，影響整體 query 效能

---

### 記憶體壓力根因

現行 `docker-compose.yaml` 問題：

```yaml
mongo:
  command: mongod --wiredTigerCacheSizeGB 4  # 8GB 主機上佔 50%
  # 無 memory limit
  # 無 volume mount（重啟後資料消失）
  # 無認證（任何人可連線）

postgres:
  # shared_buffers 預設 128MB（偏低）
  # 無 memory limit

app / collector / redis:
  # 均無 memory limit
```

---

## 功能需求（Functional Requirements）

### FR-1：MongoDB 記憶體調整

- **FR-1.1** 將 `wiredTigerCacheSizeGB` 從 4 調整為 ≤ 1.5 GB
- **FR-1.2** 為 mongo container 設定 `mem_limit`，防止 OOM 時影響其他服務
- 計算依據：`wiredTigerCache = (totalRAM - 1GB) × 0.5`，但需保留給其他服務；
  8GB 系統建議 cache = 1.5 GB，container limit = 2.0 GB

### FR-2：PostgreSQL 記憶體調整

- **FR-2.1** 透過環境變數設定 `shared_buffers = 256MB`（從 128MB 提升）
- **FR-2.2** 設定 `effective_cache_size = 1GB`，讓 query planner 做出更佳選擇
- **FR-2.3** 為 postgres container 設定 `mem_limit = 1GB`

### FR-3：MongoDB 認證

- **FR-3.1** 啟用 MongoDB auth（`--auth` flag）
- **FR-3.2** 建立 root 使用者和 app 專用使用者（最小權限）
- **FR-3.3** App 的 `MONGO_URI` 改為帶帳密格式：`mongodb://user:pass@mongo:27017/ems`
- **FR-3.4** 帳密透過 Docker secret 或 `.env` 注入，不 hardcode 在 compose 檔

### FR-4：Volume Mount（資料持久化）

- **FR-4.1** MongoDB 掛載 named volume 至 `/data/db`
- **FR-4.2** PostgreSQL 掛載 named volume 至 `/var/lib/postgresql/data`
- **FR-4.3** Redis 若需要持久化（AOF/RDB），掛載 named volume 至 `/data`
- **FR-4.4** Volume 定義在 compose `volumes:` 頂層區塊，不用 bind mount

### FR-5：Redis 記憶體上限

- **FR-5.1** 透過 `redis.conf` 或 command 設定 `maxmemory 256mb`
- **FR-5.2** 設定 `maxmemory-policy allkeys-lru`（cache 用途；session 另行評估）
- **FR-5.3** 為 redis container 設定 `mem_limit = 512MB`

### FR-6：App / Collector 容器限制

- **FR-6.1** app container：`mem_limit = 512MB`，`memswap_limit = 512MB`（停用 swap）
- **FR-6.2** collector container：`mem_limit = 256MB`
- **FR-6.3** traefik container：`mem_limit = 256MB`

---

## 非功能需求（Non-Functional Requirements）

### NFR-1：記憶體預算（8GB 主機）

全系統記憶體分配目標：

| 元件 | Container Limit | 實際預估用量 | 說明 |
|------|----------------|------------|------|
| OS + kernel | — | 1.0–1.5 GB | 保留給系統 |
| mongo | 2.0 GB | 1.5–1.8 GB | WiredTiger cache 1.5 GB + 連線開銷 |
| postgres | 1.0 GB | 256–512 MB | shared_buffers 256 MB + work_mem |
| redis | 512 MB | 128–256 MB | maxmemory 256 MB |
| app | 512 MB | 200–350 MB | Node.js heap |
| collector | 256 MB | 100–150 MB | 輕量寫入程序 |
| traefik | 256 MB | 50–100 MB | reverse proxy |
| **合計** | **~4.5 GB limit** | **~3.4–4.7 GB** | 留有 >1.5 GB buffer |

### NFR-2：容器 OOM 行為定義

- 若容器超過 `mem_limit`，Docker 預設會觸發 OOM Killer 將該容器終止
- 設定 `restart: unless-stopped` 確保自動重啟
- **mongo 被 OOM kill** 影響最大（寫入中斷、可能 WiredTiger journal 需 recovery），應優先保留足夠 headroom
- **redis 被 OOM kill** 導致 session 遺失（如果無 persistence），需考慮 `maxmemory-policy`
- **app 被 OOM kill** 對 connection 有影響，Traefik 會在重啟前返回 502

### NFR-3：磁碟容量（50GB 主機）

| 元件 | 估算 | 說明 |
|------|------|------|
| MongoDB data | 500–650 MB/月成長 | 現行 35 device-attrs × 10s interval |
| MongoDB oplog | 通常 5% disk，約 2.5 GB | 需設定 `oplogSizeMB` |
| PostgreSQL data | < 100 MB/年 | dashboard configs 少量 |
| Redis AOF（可選）| < 256 MB | 若啟用 |
| Docker images | ~2–3 GB | app + DB images |
| 系統 / logs | ~5 GB | pino logs 需 rotation |
| **可用 lifetime（12 個月）** | 50 - 10 (system) - 3 (images) = **37 GB data** | 約可撐 **56 個月**的遙測資料 |

> 設定 MongoDB TTL index（例如保留 90 天）可大幅降低磁碟成長壓力。

### NFR-4：安全性

- MongoDB 不得在無認證模式下暴露連接埠至 host（`ports:` 不應暴露 27017）
- 密碼不得出現在 compose 檔版本控制內（應使用 `.env` + `.gitignore`）
- Redis 應設定 `bind 127.0.0.1`（容器內部），不對外暴露 6379

### NFR-5：可維運性

- compose 修改後，`docker compose up -d` 應能在不遺失資料的情況下重新套用設定
- MongoDB auth 啟用後，若資料庫已有既存資料，需提供 migration 步驟（先建帳號再啟用 `--auth`）
- 所有設定變更需記錄在 README，包含計算依據

---

## 已知問題（src/index.ts 程式碼缺陷）

以下問題雖不在 Ticket 1 範圍內，但與記憶體/資源管理有關，建議連帶修正：

| 問題 | 位置 | 影響 |
|------|------|------|
| `POST /api/telemetry` 每次 request 建立新 MongoClient 且不關閉 | `index.ts:124` | 連線洩漏，最終耗盡 MongoDB 連線池 |
| `getMongo()` 無 pool size limit | `index.ts:16` | 預設 100 連線，高負載下吃記憶體 |
| `GET /api/telemetry/latest` 全集合掃描 | `index.ts:94` | 2M docs 無 index，查詢慢且佔 WiredTiger cache |
