# Ticket 1 — Database Misconfiguration

## 對應 Assignment 要求（Ticket 1 checklist）

| Assignment 要求 | 狀態 | 實作位置 |
|---|---|---|
| 針對 8GB 主機調整 MongoDB / Postgres 記憶體，展示計算 | ✅ 完成 | docker-compose.yaml + 本文計算依據 |
| 每個 service 加上 Docker memory limit | ✅ 完成 | docker-compose.yaml `mem_limit` |
| 開啟 MongoDB 認證 | ✅ 完成 | `--auth` + mongo-init + `.env` |
| 修好 volume mount，確保資料持久化 | ✅ 完成 | named volumes via `VOLUME_PATH` |
| 說明 service 超過記憶體上限的行為 | ✅ 完成 | 本文 NFR-2 |

---

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
| 加上 index（compound index (deviceId, timestamp)）| +~150 MB |

---

## 功能需求與實作（Functional Requirements）

### FR-1：MongoDB 記憶體調整 ✅

- **FR-1.1** `wiredTigerCacheSizeGB` 從 4 調整為 **1.5 GB**
- **FR-1.2** mongo container `mem_limit: 2g`（cache 1.5 GB + 連線開銷 headroom）

**計算依據：**
```
wiredTigerCache = (8GB - 1GB) × 0.5 = 3.5GB（MongoDB 公式預設值）
但需保留給其他服務 → 保守設定為 1.5 GB
container limit = cache (1.5GB) + 連線/heap 開銷 (~0.5GB) = 2.0 GB
```

**docker-compose.yaml 對應：**
```yaml
mongo:
  command: mongod --auth --wiredTigerCacheSizeGB 1.5
  mem_limit: 2g
  memswap_limit: 2g
```

---

### FR-2：PostgreSQL 記憶體調整 ✅

- **FR-2.1** `shared_buffers = 256MB`（從預設 128MB 提升）
- **FR-2.2** `effective_cache_size = 1GB`（讓 query planner 更準確估算可用快取）
- **FR-2.3** postgres container `mem_limit: 1g`

**計算依據：**
```
shared_buffers 建議 = 系統 RAM 的 25%（PostgreSQL 官方建議）
8GB × 25% = 2GB，但因 mongo 已佔大部分，保守設定 256MB
effective_cache_size = shared_buffers + OS page cache 估算 ≈ 1GB
container limit 1GB = shared_buffers (256MB) + work_mem + 連線開銷
```

**docker-compose.yaml 對應：**
```yaml
postgres:
  command: >
    postgres
    -c shared_buffers=256MB
    -c effective_cache_size=1GB
  mem_limit: 1g
  memswap_limit: 1g
```

---

### FR-3：MongoDB 認證 ✅

- **FR-3.1** 啟用 `--auth` flag
- **FR-3.2** 透過 `mongo-init/` 初始化腳本建立 root 使用者和 app 專用使用者（最小權限：`readWrite` on `ems` DB）
- **FR-3.3** App 的 `MONGO_URI = mongodb://app:<pass>@mongo:27017/ems`
- **FR-3.4** 帳密透過 `.env` 注入，不 hardcode 在 compose 檔

**安全設計：**
- root user 僅用於初始化，app 使用最小權限帳號
- `.env` 加入 `.gitignore`，`.env.example` 僅保存範本（無真實密碼）
- 不對外暴露 mongo 27017 port（僅 Docker internal network）

---

### FR-4：Volume Mount（資料持久化）✅

- **FR-4.1** MongoDB → `${VOLUME_PATH}/mongo-data:/data/db`
- **FR-4.2** PostgreSQL → `${VOLUME_PATH}/postgres-data:/var/lib/postgresql/data`
- **FR-4.3** Redis → `${VOLUME_PATH}/redis-data:/data`

**設計說明：**
- 使用 `VOLUME_PATH` 環境變數（預設 `.data`），方便不同環境（dev/production）切換路徑
- 本機 dev 預設 `.data/`（在 `.gitignore` 中），production 建議設為 `/opt/ems/data`
- 使用 bind mount 而非 Docker named volume，讓 `docker compose down -v` 不會誤刪資料

---

### FR-5：Redis 記憶體上限 ✅

- **FR-5.1** `maxmemory 256mb`
- **FR-5.2** `maxmemory-policy allkeys-lru`（cache 用途）
- **FR-5.3** redis container `mem_limit: 512m`

**docker-compose.yaml 對應：**
```yaml
redis:
  command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru
  mem_limit: 512m
  memswap_limit: 512m
```

---

### FR-6：App / Collector / Traefik 容器限制 ✅

| 容器 | mem_limit | memswap_limit | 說明 |
|------|-----------|--------------|------|
| app | 512m | 512m | Node.js heap，停用 swap |
| collector | 256m | 256m | 輕量寫入程序 |
| traefik | 256m | 256m | reverse proxy |

---

## 非功能需求（Non-Functional Requirements）

### NFR-1：記憶體預算（8GB 主機）

全系統記憶體分配：

| 元件 | Container Limit | 實際預估用量 | 說明 |
|------|----------------|------------|------|
| OS + kernel | — | 1.0–1.5 GB | 保留給系統 |
| mongo | **2.0 GB** | 1.5–1.8 GB | WiredTiger cache 1.5 GB + 連線開銷 |
| postgres | **1.0 GB** | 256–512 MB | shared_buffers 256 MB + work_mem |
| redis | **512 MB** | 128–256 MB | maxmemory 256 MB |
| app | **512 MB** | 200–350 MB | Node.js heap |
| collector | **256 MB** | 100–150 MB | 輕量寫入程序 |
| traefik | **256 MB** | 50–100 MB | reverse proxy |
| **Container limits 合計** | **~4.5 GB** | **~3.4–4.7 GB** | 留有 >1.5 GB buffer |

原本 wiredTigerCacheSizeGB = 4 會讓 mongo 單獨吃掉 4+ GB，加上其他服務直接觸發 swap。調整後整體 limits 合計約 4.5 GB，有 >3 GB 的安全緩衝。

---

### NFR-2：容器 OOM 行為定義（Assignment 必答項）

當容器超過 `mem_limit`，Docker 的 Linux cgroup 會觸發 **OOM Killer**，強制終止該容器（不影響其他容器）。

| 容器 | 被 OOM kill 的影響 | 緩解方式 |
|------|-------------------|---------|
| **mongo** | 最嚴重：寫入中斷，WiredTiger journal 需 recovery，正在進行的事務全部回滾 | 設定足夠 headroom（limit 2GB > cache 1.5GB），`restart: unless-stopped` 自動重啟後 journal recovery |
| **postgres** | 進行中的 query 失敗，app 端拋 connection error | `restart: unless-stopped`，連線池自動重連 |
| **redis** | Session / cache 全部遺失（若無 persistence）| `allkeys-lru` 讓 redis 在記憶體不足前主動淘汰，AOF 可選（影響效能） |
| **app** | 正在處理的 HTTP request 中斷，Traefik 返回 502 | `restart: unless-stopped`，client 重試即可 |
| **collector** | 當前 cycle 資料遺失（10 秒間隔），下個 cycle 恢復 | 資料量少，影響可接受 |

**`memswap_limit = mem_limit`** 設定停用 swap，避免 OOM 前的效能劣化期（swap thrashing 比直接 OOM kill 更難診斷）。

---

### NFR-3：磁碟容量（50GB 主機）

| 元件 | 估算 | 說明 |
|------|------|------|
| MongoDB data | 500–650 MB/月成長 | 35 device-attrs × 10s interval |
| PostgreSQL data | < 100 MB/年 | dashboard configs 少量 |
| Redis data（AOF 可選）| < 256 MB | 若啟用 |
| Docker images | ~2–3 GB | app + DB images |
| 系統 / logs | ~5 GB | pino logs 需 rotation |
| **可用 lifetime（12 個月）** | 50 - 10 (system) - 3 (images) = **37 GB** | 約可撐 **56 個月**的遙測資料 |

> 建議設定 MongoDB TTL index（保留 90 天）大幅降低磁碟成長壓力。

---

### NFR-4：安全性

- MongoDB 不暴露 27017 port 至 host（僅 Docker internal `backend` network）
- 密碼僅存於 `.env`（加入 `.gitignore`），compose 檔無 hardcode 密碼
- `.env.example` 提供範本，標示需替換的欄位
- Redis 僅在 Docker internal network，不對外暴露 6379

---

### NFR-5：可維運性

- `docker compose up -d` 套用設定後，volume 資料不遺失
- MongoDB auth 啟用注意事項：
  - 新安裝：`docker compose up` 時 `mongo-init/` 腳本自動建立帳號
  - 已有資料的遷移：需先在無 auth 模式下建帳號，再加 `--auth` flag 重啟
- `VOLUME_PATH` 環境變數讓不同站點（production vs dev）使用不同資料路徑

---

## 已知問題（Ticket 1 範圍外，建議連帶修正）

| 問題 | 位置 | 影響 |
|------|------|------|
| `POST /api/telemetry` 每次 request 建立新 MongoClient 且不關閉 | `index.ts:124` | 連線洩漏，最終耗盡 MongoDB 連線池 |
| `getMongo()` 無 pool size limit | `index.ts:16` | 預設 100 連線，高負載下吃記憶體 |
| `GET /api/telemetry/latest` 全集合掃描 | `index.ts:94` | 2M docs 無 index，查詢慢且佔 WiredTiger cache |

---

## README 內容草稿（Ticket 1 段落）

> 以下為 README 中 Ticket 1 對應段落的草稿，完整 README 另見 `README.md`。

### Ticket 1: Database Misconfiguration — 修正說明

#### 問題描述

原始 stack 有以下幾個問題：
1. MongoDB WiredTiger cache 設為 4GB，在 8GB 主機上與其他服務競爭，造成 swap
2. 所有容器無 memory limit，任一服務 OOM 會影響整機
3. MongoDB 無認證，任何人可直連
4. 無 volume mount，容器重啟後資料全部消失
5. PostgreSQL `shared_buffers` 僅 128MB（預設值，偏低）

#### 記憶體分配計算

8GB 主機記憶體預算分配（詳見 work1.md NFR-1）：

| 服務 | Container Limit | 說明 |
|------|----------------|------|
| OS + kernel | 保留 ~1.5 GB | 不設 limit |
| mongo | 2 GB | wiredTigerCache 1.5 GB + 連線開銷 |
| postgres | 1 GB | shared_buffers 256 MB |
| redis | 512 MB | maxmemory 256 MB |
| app | 512 MB | Node.js |
| collector | 256 MB | — |
| traefik | 256 MB | — |
| **合計 limits** | **~4.5 GB** | 留有 >1.5 GB buffer |

WiredTiger cache 計算：MongoDB 官方公式 `(RAM - 1GB) × 0.5 = 3.5 GB`，但需保留給其他服務，保守設定 1.5 GB。

#### OOM 行為說明

超過 `mem_limit` 時，Docker（Linux cgroup）觸發 OOM Killer 強制終止該容器，不影響其他容器。`restart: unless-stopped` 確保自動重啟。最嚴重的是 mongo 被 OOM kill（WiredTiger journal 需 recovery）；`memswap_limit = mem_limit` 停用 swap 避免效能劣化期。

#### 部署方式

```bash
# 複製 .env.example，填入密碼
cp .env.example .env
# 設定資料存放路徑（production 建議 /opt/ems/data）
echo "VOLUME_PATH=/opt/ems/data" >> .env

docker compose up -d
```
