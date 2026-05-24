# Work Plan — DevOps Take-Home

> 分析日期：2026-05-24  
> 建議完成：Ticket 1, 3, 6, 7（T3 + T7 必填，T1 + T6 選做）

---

## 現況快速盤點

從 `docker-compose.yaml` 和 `src/index.ts` 可以看到有意留下的 bug：

| 位置 | 問題 |
|------|------|
| `docker-compose.yaml:30` | MongoDB cache 4GB（主機只有 8GB）|
| `docker-compose.yaml:33` | MongoDB 無認證 |
| `docker-compose.yaml` | 所有服務無 volume mount，重啟資料消失 |
| `docker-compose.yaml` | 所有服務無 memory limit |
| `src/index.ts:124` | POST /api/telemetry 每次 request 開新 MongoClient，從不關閉（connection leak）|
| `src/index.ts:93` | GET /api/telemetry/latest 在未建 index 的 collection 跑 aggregation |
| `src/index.ts:29` | Postgres pool max=5（很小，但不是最緊急的問題）|

---

## Ticket 選擇與優先順序

```
優先序：T3 > T1 > T7 > T6
跳過：T2（備份 pipeline 複雜）、T4（zero-downtime deploy）、T5（GitOps）
```

**選擇理由：**
- T3 必填，且架構設計最能展現能力，工時最大
- T1 基礎修復，影響所有其他 ticket 的穩定性，必須先做
- T7 必填，純寫作，做完 T1/T3 後文字會更有說服力
- T6 呼應面試情境（評估者會用 Claude Code 實測），CP 值高

---

## Ticket 1：Database Misconfiguration

**目標：** 修正 docker-compose.yaml 的記憶體、認證、資料持久化問題

### 記憶體預算計算（寫入 README）

```
8GB 主機總 RAM 分配：
  OS + kernel buffer     : 1.0 GB
  App (Node.js)          : 0.5 GB  → memory limit 512m
  Collector (Node.js)    : 0.3 GB  → memory limit 256m
  MongoDB wiredTiger cache: 1.5 GB → --wiredTigerCacheSizeGB 1.5
  MongoDB 其他開銷       : 0.5 GB  → memory limit 2g
  PostgreSQL shared_buffers: 0.5 GB → POSTGRES_SHARED_BUFFERS=512MB
  PostgreSQL work_mem 等  : 0.3 GB  → memory limit 1g
  Redis                  : 0.4 GB  → memory limit 512m + maxmemory 256mb
  預留 headroom          : 3.0 GB
```

### 工作項目

- [ ] **記憶體設定**
  - `docker-compose.yaml` → MongoDB: `--wiredTigerCacheSizeGB 1.5`
  - Postgres: 加入 `command: postgres -c shared_buffers=512MB -c work_mem=16MB`
  - Redis: 加入 `command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru`

- [ ] **Docker memory limits**（每個 service 加 `deploy.resources.limits.memory`）
  - app: 512m
  - collector: 256m
  - mongo: 2g
  - postgres: 1g
  - redis: 512m

- [ ] **MongoDB 認證**
  - mongo service 加 `MONGO_INITDB_ROOT_USERNAME` / `MONGO_INITDB_ROOT_PASSWORD` env
  - `command` 加 `--auth`
  - app/collector 的 `MONGO_URI` 改成含帳密的格式
  - 用 `.env` 管理密碼（.env 加進 .gitignore）

- [ ] **Volume mounts（資料持久化）**
  - mongo: `mongo-data:/data/db`
  - postgres: `pg-data:/var/lib/postgresql/data`
  - redis: `redis-data:/data` + `--appendonly yes`
  - 在 `volumes:` 區塊定義 named volumes

- [ ] **README 說明**
  - 記憶體分配計算過程
  - 如果某 service 超過 memory limit 會發生什麼（OOMKilled，Docker 重啟，Swarm 重新調度）
  - 認證設計說明

**預估工時：** 2 小時

---

## Ticket 3：Central Multi-Site Observability（必填）

**目標：** 建立中央監控平台，3 個邊緣站點把 metrics + logs 推送過來

### 架構設計

```
┌─────────────────────────────────────────────────────────┐
│                    Central Platform                      │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐ │
│  │  Prometheus  │  │    Loki      │  │   Grafana     │ │
│  │  (metrics    │  │  (logs       │  │  (dashboard   │ │
│  │   storage)   │  │   storage)   │  │   + alerts)   │ │
│  └──────────────┘  └──────────────┘  └───────────────┘ │
│         ▲                 ▲                              │
│         │  push           │  push                       │
└─────────┼─────────────────┼────────────────────────────-┘
          │                 │
┌─────────┴────────────────-┴──────────────────┐
│         Edge Site (×3, 模擬 3 個站點)         │
│  ┌──────────────────────────────────────────┐│
│  │           Grafana Alloy                  ││
│  │  - 收集 container metrics (cAdvisor)     ││
│  │  - 收集 node metrics (node_exporter)     ││
│  │  - 收集 app logs (/var/log/docker/...)   ││
│  │  - 推送 metrics → Prometheus (push)      ││
│  │  - 推送 logs → Loki                      ││
│  └──────────────────────────────────────────┘│
│  app / collector / mongo / postgres / redis   │
└──────────────────────────────────────────────┘

傳輸方式：
  Metrics: Alloy → Prometheus remote_write endpoint
  Logs:    Alloy → Loki push API
  方向：全部從 edge 主動推出（edge 不需要開 inbound port）
```

### 目錄結構規劃

```
observability/
├── central/
│   ├── docker-compose.yaml       # Prometheus + Loki + Grafana
│   ├── prometheus/
│   │   └── prometheus.yml        # 接收 remote_write
│   ├── loki/
│   │   └── loki-config.yaml
│   └── grafana/
│       ├── provisioning/
│       │   ├── datasources/      # Prometheus + Loki datasource
│       │   └── dashboards/       # 自動載入 dashboard JSON
│       └── dashboards/
│           ├── overview.json     # 所有站點一覽
│           └── site-detail.json  # 單站點 drilldown
├── edge/
│   ├── alloy/
│   │   └── config.alloy          # Alloy 設定（帶 site_id label）
│   └── docker-compose.edge.yaml  # 站點 compose override（加 Alloy）
└── simulate/
    ├── site-1/docker-compose.yaml
    ├── site-2/docker-compose.yaml
    └── site-3/docker-compose.yaml
```

### 工作項目

- [ ] **Central platform（`observability/central/docker-compose.yaml`）**
  - Prometheus（remote_write receiver 模式）
  - Loki（filesystem storage）
  - Grafana（provision datasources + dashboards）

- [ ] **Prometheus 設定**
  - 開啟 `--web.enable-remote-write-receiver`
  - 設定 retention（15天）

- [ ] **Loki 設定**
  - single binary mode（輕量，12 站點足夠）
  - filesystem storage

- [ ] **Grafana 設定**
  - Auto-provision datasources（Prometheus + Loki）
  - Auto-provision dashboards（overview + site-detail）

- [ ] **Grafana Dashboard: All-Sites Overview**
  - 每個 site 的 status（up/down）
  - 每個 site 的 container 數量
  - 每個 site 的記憶體使用率
  - 每個 site 最後回報時間

- [ ] **Grafana Dashboard: Site Detail**
  - container 狀態（app / collector / mongo / postgres / redis）
  - MongoDB 記憶體使用
  - disk 使用
  - 最近 logs（Loki 查詢）

- [ ] **Alert 設定**
  - `SiteOffline`: 站點 >5 分鐘沒有 metrics 進來
  - `CriticalServiceDown`: app container 停止回報

- [ ] **Grafana Alloy 設定（`observability/edge/alloy/config.alloy`）**
  - 收集 Docker container metrics（cAdvisor 或 Alloy 內建）
  - 收集 Node 基本 metrics（CPU/RAM/disk）
  - 收集 container logs
  - 加入 `site_id` label
  - 推送 metrics → `CENTRAL_PROMETHEUS_URL`
  - 推送 logs → `CENTRAL_LOKI_URL`

- [ ] **模擬 3 個站點**
  - `simulate/site-{1,2,3}/docker-compose.yaml`
  - 每個站點獨立 network，各自跑 app + alloy
  - 用不同 port 區分（3001, 3002, 3003）

- [ ] **驗收測試**
  - 起 central + 3 sites
  - 確認 Grafana overview 顯示 3 個站點
  - 關掉 site-1，確認 alert 觸發
  - 重新上線 site-1，確認恢復

- [ ] **README 說明**
  - 架構圖
  - 每層選型理由（Alloy vs Promtail、push vs pull）
  - edge 資源佔用評估（Alloy 約 50-100MB RAM）
  - 擴展到 50 站點的瓶頸（Prometheus 記憶體、Loki ingestion rate）
  - 站點離線後重新上線的 buffer 行為

**預估工時：** 8-10 小時

---

## Ticket 6：AI-Assisted Operations Handoff

**目標：** 讓非 DevOps 同事透過 Claude Code 處理日常維運

### 設計方向

使用 `CLAUDE.md` + 專用 shell scripts 組合：
- CLAUDE.md：提供 Claude 理解系統的背景知識、runbook、危險操作清單
- Scripts：標準化操作步驟，讓 Claude 可以引導同事執行

### 目錄結構

```
ops/
├── health-check.sh     # 檢查所有服務健康狀態
├── deploy.sh           # 部署新版本
├── rollback.sh         # 回滾到上一個版本
├── investigate.sh      # 調查站點問題
├── backup-check.sh     # 檢查備份狀態
└── README.md           # 腳本使用說明
CLAUDE.md               # Claude 的 ops 指南
```

### 工作項目

- [ ] **CLAUDE.md 內容**
  - 系統架構簡介（stack、services、端口）
  - 5 個常見操作的 runbook（含範例指令）
  - 危險操作清單（附警告文字）
  - 不知道怎麼做時的 escalation 路徑

- [ ] **`ops/health-check.sh`**
  - `docker compose ps` 狀態
  - HTTP health check（`/health`）
  - MongoDB ping
  - PostgreSQL query test
  - Redis ping
  - 輸出：綠色 OK / 紅色 FAIL

- [ ] **`ops/deploy.sh <IMAGE_TAG>`**
  - 驗證 image tag 存在
  - 備份當前設定
  - 更新 compose，滾動重啟
  - 等待 healthcheck 通過
  - 失敗時自動回滾

- [ ] **`ops/rollback.sh`**
  - 列出最近 3 個版本
  - 讓使用者確認後 rollback
  - 需要明確輸入確認（防誤觸）

- [ ] **`ops/investigate.sh`**
  - 顯示 container logs（最近 100 行）
  - 顯示 docker stats（CPU/RAM）
  - 顯示 disk 使用
  - 顯示最近的 errors

- [ ] **README 說明**
  - 涵蓋哪些場景
  - 刻意不涵蓋什麼（及原因）
  - Claude 在哪些情況下需要人介入

**預估工時：** 3 小時

---

## Ticket 7：Prioritization and Multi-Site Strategy（必填）

> README only，根據完成 T1/T3/T6 後的實際經驗撰寫

### 工作項目

- [ ] **優先順序說明**（含理由）
  1. T1 Database（基礎穩定性，其他 ticket 的前提）
  2. T3 Observability（客戶站點最大風險：問題無法察覺）
  3. T7 Strategy（必填）
  4. T6 AI Handoff（降低人力依賴）
  5. T4 Deploy（減少停機）
  6. T2 Backup（DR 重要但不緊急）
  7. T5 GitOps（長期工具，優先序最低）

- [ ] **需要 pushback 的 ticket**
  - T2: S3 在台灣/中國是否可用？每個站點的網路費用預算？
  - T4: 目前是否有 CI/CD 系統？還是純 SSH 手動？
  - T5: Git 選哪個平台？站點可以 outbound 到 GitHub 嗎？

- [ ] **12 站點先建什麼**
  1. Observability（T3）— 沒有能見度就沒有一切
  2. 統一 secret 管理（.env template + 站點覆寫）
  3. T1 的設定標準化（deploy template）
  4. 簡單的 deploy script（T6 ops scripts）

**預估工時：** 1.5 小時

---

## 總工時估計

| Ticket | 工時 | 類型 |
|--------|------|------|
| T1 Database misconfiguration | 2h | 實作 |
| T3 Observability | 8-10h | 實作 |
| T6 AI Handoff | 3h | 實作 |
| T7 Prioritization | 1.5h | README |
| README 整理 | 1h | 文件 |
| **合計** | **15-17h** | |

---

## 執行順序

```
Day 1: T1（2h）→ T3 central platform（4h）
Day 2: T3 edge agents + dashboards + alerts（5h）
Day 3: T3 驗收 + T6（3h）→ T7 README（1.5h）→ 整體 README（1h）
```

---

## 跳過的 Ticket 理由

| Ticket | 跳過原因 |
|--------|---------|
| T2 Backup | 需要真實 S3 環境驗證；設計可寫入 T7，但完整實作 restore.sh 工時大 |
| T4 Zero-downtime deploy | Blue-green 在單機 compose 上價值有限；T1 修好後停機從 30s 降到 ~5s 已夠 |
| T5 GitOps | 12 站點 SSH 管理可先用 Ansible 臨時解決；GitOps 是 nice-to-have |
