# DevOps Take-Home

## Summary

| 優先序 | Ticket | 名稱 | 狀態 | 預估工時 |
|--------|--------|------|------|---------|
| 1 | T4 | Zero-Downtime Deploy | ✅ 完成 | 3h |
| 1 | T2 | Backup Pipeline | — 跳過（需討論） | — |
| 2 | T3 | Central Multi-Site Observability | 🔄 進行中 | 8–10h |
| 2 | T1 | Database Misconfiguration | ✅ 完成 | 2h |
| 3 | T5 | GitOps | — 跳過（待 T4/T1 穩定後） | — |
| 3 | T6 | AI-Assisted Operations Handoff | ⬜ 未完成 | 3h |
| — | T7 | Prioritization & Multi-Site Strategy | ✅ 完成 | 1.5h |

**執行順序：** T4 → T1 → T6（依序），T3 與三者並行作業

---

## Ticket 4：Zero-Downtime Deploy ✅

藍綠部署機制，透過 Traefik 動態路由切換，不中斷對外服務。

### 完成內容

- `backend/deploy.sh`：藍綠部署腳本
  - 啟動 green 容器 → health check 通過後切換 Traefik → 停止 blue 容器
  - health check 失敗時自動回滾
- `backend/traefik/`：Traefik 靜態與動態路由設定
- `backend/migrate/index.ts`：部署前自動執行 schema migration（建立複合索引、backfill）

### 部署流程

```
make deploy VERSION=v2
  └─ 驗證 image
  └─ 執行 migration
  └─ 啟動 app-new:3001 (green)
  └─ GET /health × 60s
  └─ 更新 Traefik dynamic config → app-new:3000
  └─ 停止舊容器 app (blue)
  └─ rename app-new → app
```

### 使用方式

```bash
# 建置 image
make image VERSION=v1

# 執行部署
make deploy VERSION=v2

# 整合測試（migration + 藍綠端對端驗證）
make migration-test
```

---

## Ticket 3：Central Multi-Site Observability 🔄

中央監控平台，收集 3 個邊緣站點的 metrics、logs、traces。

### 已完成

- **Helm umbrella chart** (`charts/`)：kube-prometheus-stack + Tempo + Alloy
- **kube-prometheus-stack**：Prometheus、Grafana、Alertmanager（含 Tempo datasource 自動設定）
- **Tempo**：分散式 tracing backend，接收 OTLP over gRPC/HTTP
- **Alloy**：OTLP collector pipeline，加入 `cluster` label 後轉送至 Tempo
- **NodePort 暴露**：Alloy 30317 (gRPC)、30318 (HTTP)

### 架構

```
Edge Site (×3)
  └─ Grafana Alloy (OTLP receiver)
       ├─ add cluster label
       └─ forward → Central Tempo :4317

Central Platform (Kubernetes)
  ├─ Tempo          (trace storage)
  ├─ Prometheus     (metrics storage)
  ├─ Alertmanager   (alerts)
  └─ Grafana        (dashboards)
```

### 待完成

- [ ] 多站點模擬（`simulate/site-{1,2,3}/`）
- [ ] Grafana All-Sites Overview dashboard
- [ ] Grafana Site Detail dashboard
- [ ] Alert 規則：`SiteOffline`、`CriticalServiceDown`
- [ ] Loki log aggregation 整合
- [ ] README：架構決策說明（Alloy vs Promtail、push vs pull）

### 快速部署

```bash
cd charts
make install        # helm upgrade --install
make uninstall      # 清除
```

---

## Ticket 1：Database Misconfiguration ✅

修正 `docker-compose.yaml` 的記憶體、認證、資料持久化問題。詳細分析與計算依據見 [plan/work1.md](plan/work1.md)。

### 完成內容

| 問題 | 修正方式 |
|------|---------|
| MongoDB WiredTiger cache 4GB（8GB 主機無法負荷）| 調整為 1.5 GB，container limit 2 GB |
| MongoDB 無認證 | 啟用 `--auth`，透過 `mongo-init/` 建立 root / app 帳號 |
| 所有服務無 volume mount，重啟後資料消失 | 掛載 bind mount，路徑由 `VOLUME_PATH` 環境變數控制 |
| 所有服務無 memory limit | 全部容器加入 `mem_limit` + `memswap_limit` |
| PostgreSQL `shared_buffers` 僅 128MB（預設值）| 調整為 256MB，加入 `effective_cache_size=1GB` |

### 記憶體分配（8GB 主機）

| 服務 | Container Limit | 說明 |
|------|----------------|------|
| OS + kernel | 保留 ~1.5 GB | 不設 limit |
| mongo | **2 GB** | wiredTigerCache 1.5 GB + 連線開銷 |
| postgres | **1 GB** | shared_buffers 256 MB + work_mem |
| redis | **512 MB** | maxmemory 256 MB |
| app | **512 MB** | Node.js heap |
| collector | **256 MB** | 輕量寫入程序 |
| traefik | **256 MB** | reverse proxy |
| **合計 limits** | **~4.5 GB** | 留有 >1.5 GB buffer |

WiredTiger cache 計算：MongoDB 官方公式 `(8GB - 1GB) × 0.5 = 3.5 GB`，但需保留給其他服務，保守設定 **1.5 GB**。

### OOM 行為

超過 `mem_limit` 時，Docker（Linux cgroup）觸發 **OOM Killer** 強制終止該容器，不影響其他服務。`restart: unless-stopped` 確保自動重啟。`memswap_limit = mem_limit` 停用 swap，避免 OOM 前的 swap thrashing 效能劣化期（比直接 OOM kill 更難診斷）。

| 容器 | 被 OOM kill 的影響 | 緩解方式 |
|------|-------------------|---------|
| **mongo** | 最嚴重：寫入中斷，WiredTiger journal recovery | limit 2 GB > cache 1.5 GB 提供 headroom |
| **postgres** | 進行中 query 失敗，app 拋 connection error | 連線池自動重連 |
| **redis** | Session / cache 全部遺失 | `allkeys-lru` 提前主動淘汰，避免觸及 limit |
| **app** | 進行中 HTTP request 中斷，Traefik 返回 502 | client 重試即可 |
| **collector** | 當前 10s cycle 資料遺失，下個 cycle 恢復 | 影響可接受 |

### 部署方式

```bash
# 複製 .env.example，填入各站點密碼
cp backend/.env.example backend/.env

# 設定資料存放路徑（production 建議 /opt/ems/data）
echo "VOLUME_PATH=/opt/ems/data" >> backend/.env

docker compose -f backend/docker-compose.yaml up -d
```

> 詳細計算依據、安全設計、磁碟容量估算見 [plan/work1.md](plan/work1.md)。

---

## Ticket 6：AI-Assisted Operations Handoff ⬜

讓非 DevOps 同事透過 Claude Code 處理日常維運，降低人力依賴。

### 設計方向

- `CLAUDE.md`：提供 Claude 系統背景、runbook、危險操作清單
- `ops/` 目錄：標準化 shell scripts，讓 Claude 引導同事安全執行

### 待完成

- [ ] `ops/health-check.sh`：檢查所有服務狀態（docker、HTTP、DB ping）
- [ ] `ops/deploy.sh <TAG>`：驗證 → 備份設定 → 滾動重啟 → 失敗自動回滾
- [ ] `ops/rollback.sh`：列出近 3 版本，需明確輸入確認
- [ ] `ops/investigate.sh`：container logs + docker stats + disk 使用
- [ ] `CLAUDE.md`：5 個常見操作 runbook + 危險操作清單 + escalation 路徑

---

## Ticket 7：Prioritization & Multi-Site Strategy ✅

### 1. 優先順序

**T4 == T2 > T3 == T1 > T5 == T6**

| 優先序 | Ticket | 理由 |
|--------|--------|------|
| 1 | **T4** Zero-Downtime Deploy | 電量調度服務是毫秒級操作。沒有 blue-green，每次更新 image 都造成服務中斷，客戶損失是確定會發生的，不是假設情境。這個風險存在於每次部署，頻率高、影響直接。 |
| 1 | **T2** Backup *(跳過)* | 地端 volume 與備份能確保資料不遺失。但需要先討論：要存什麼、多久一次、存哪裡、如何驗證 restore、rollback 流程——這些不是 30 分鐘能決定的，需要與 stakeholder 對齊後才能實作。本次跳過，但重要性等同 T4。 |
| 2 | **T3** Central Observability | 服務需要 24/7 不間斷。建立觀測系統能讓管理者與廠商第一時間收到通知，從「客戶打來才知道」變成「我們比客戶先知道」。良好的 metric 與 log 也讓開發者有資料能優化軟體，是長期降低事故成本的基礎。 |
| 2 | **T1** Database Misconfiguration | 資源不是無限的。沒有 memory limit 且 MongoDB cache 設為 4GB，在 8GB 主機上跑一段時間後必然 OOMKill，造成不可預期的服務中斷。這不是效能優化，是基礎可靠性問題。 |
| 3 | **T5** GitOps | 受 T4、T2、T1 影響——唯有 deploy 流程、backup 策略、資源設定確定後，才能設計出合理的地端設定管理。現在做只是把不穩定的現狀自動化。 |
| 3 | **T6** AI Handoff | 同 T5。需要先有穩定的基礎設施與標準化操作流程，才能讓 Claude 引導同事安全地執行維運任務。在流程未定前，AI handoff 只是讓人更快地做錯事。 |

---

### 2. 需要 Pushback 的 Ticket

**T2 — Backup Pipeline**

在設計備份策略之前，需要先確認：
- **存哪裡**：S3 在台灣或客戶站點所在地的可用性與費用（部分站點可能無法出境）
- **頻率與保留**：MongoDB 每天長 200MB，Postgres 較慢——可以接受多少資料遺失（RPO）？
- **頻寬預算**：站點頻寬 10–100Mbps 差距很大，全量備份的時間窗口能否接受？
- **Restore 演練**：備份沒有定期測 restore 等於沒有備份，這個工作流要如何納入日常？

**T4 — Zero-Downtime Deploy**

- 目前站點是純 SSH 手動部署，還是已有 CI/CD pipeline？這影響 deploy.sh 要設計成誰呼叫、觸發方式是什麼。
- migration 失敗後的 DB rollback 策略：index drop 是冪等的，但 backfill 的欄位要怎麼清？

**T5 — GitOps**

- Git 平台選哪個？站點可以 outbound 連到 GitHub/GitLab 嗎？有的站點網路隔離，webhook-based GitOps 根本無法運作。
- Secrets 管理：12 個站點各有不同 DB 密碼，plaintext 不能進 repo，需要確認現有的 secret 管理方式（目前用 .env 手動管理，這個狀態要先改好才能談 GitOps）。

---

### 3. 12 站點的優先建設順序

讓各站點操作者能統一部署、不需要理解內部實作，最小可行方案只有兩件事：

**① `deploy.sh` — 統一部署入口**

`backend/deploy.sh` 已透過環境變數參數化（`MONGO_URI`、`PG_URI`），操作者只需執行：

```bash
source .env && ./deploy.sh <image:tag>
```

blue-green 切換、Traefik 路由、health check、rollback 全在腳本內，操作者不需要知道細節。網路環境問題（從外面連不進去）也不是障礙——腳本在站點機器上本地執行，透過 SSH 觸發即可。

**② `.env.template` — 站點變數標準化**

定義所有必填變數，各站點維護自己的 `.env`：

```bash
# .env.template
MONGO_URI=mongodb://mongo:27017/ems   # 填入各站點實際 URI
PG_URI=postgresql://user:pass@host/db  # 填入各站點實際 URI
DOMAIN=your-site.example.com
```

每個站點 copy template、填入自己的 domain、DB 密碼、網路設定，其餘全用共同腳本。12 個站點不同，但部署流程只有一份。

---

## 跳過的 Ticket

| Ticket | 原因 |
|--------|------|
| T2 Backup | 需真實 S3 環境驗證；設計思路寫入 T7 |
| T5 GitOps | 12 站點 SSH 管理可先用 Ansible 臨時解決；GitOps 是 nice-to-have |

---

## 題目修改說明

### Ticket 4：從 k3s variant 改為 Blue-Green + Traefik

**怎麼改的**

原題目提供三條路：compose rolling restart、blue-green、或 k3s Deployment（Optional variant）。題目也特別說明 k3s 路線能展示 Kubernetes 能力，對公司有參考價值。

我選擇了 **blue-green + Traefik 動態路由**，而非 k3s。具體做法：
- `deploy.sh` 直接操作 Docker container（`docker run` 啟動 app-new，curl health check，`mv` 覆寫 Traefik dynamic config，`docker rm` 舊容器，`docker rename` 收尾）
- Traefik file-watcher 偵測到 `traefik/dynamic/app.yml` 變更後自動 reload，實現 atomic upstream 切換
- `rename` 在 config 寫入後才執行，利用 Traefik ~1s reload 延遲避免 race condition（config 指向 `app:3000` 但此時容器名仍是 `app-new`，rename 完成時 Traefik 才切換完畢）

**為什麼改**

兩個原因都有：

1. **更貼近職位需求**：題目情境是 12 個客戶邊緣站點，每台 8GB RAM。k3s 本身的 control plane 佔用約 512MB–1GB，加上 etcd、kubelet 等，在資源受限的邊緣主機上會擠壓給 app、MongoDB、Postgres 用的空間，與 T1 的記憶體優化方向相反。選擇停留在 docker-compose 層級，讓部署機制與現有 stack 一致，維運複雜度也不增加。

2. **展現能力**：用 proxy layer（Traefik）做 atomic 切換，比 `docker-compose up --no-deps app` rolling restart 多展示一層：proxy 配置管理、file-watcher reload 時序、rename race condition 分析。這是 compose 方案做不到的。

**多覆蓋了哪些能力 / 少測了哪些**

| | 說明 |
|--|------|
| 多覆蓋 | Traefik 動態路由配置（static/dynamic 分層）；atomic config swap 的時序設計；deploy log 自動寫檔供事後稽核 |
| 少測 | **Kubernetes 能力**：k3s Deployment rollout、readiness/liveness probe 配置、Job-based migration 執行順序、K8s 層面的 rollback（DB state 已變更時怎麼處理）——這些是 k3s 路線才能展示的東西，本方案完全沒有觸及 |

---

### Ticket 3：加入 Tempo（Distributed Tracing），暫未完成 Loki

**怎麼改的**

題目明確建議的 stack 是 **Grafana + Prometheus + Loki + Alloy/Promtail**（metrics + logs）。我在此基礎上加入了 **Tempo**（distributed tracing），讓方案涵蓋觀測性三支柱，但 **Loki 尚未完成**。

具體實作：
- Helm umbrella chart（`charts/`）組合 kube-prometheus-stack + Tempo + Alloy
- Alloy 作為 OTLP receiver，注入 `cluster` label 後轉送至 Tempo（gRPC :4317）
- kube-prometheus-stack 自動注入 Tempo datasource 至 Grafana
- NodePort 30317/30318 供邊緣站點推送 trace 資料

**為什麼改**

以展現能力為主：

Grafana stack 的三支柱（metrics / logs / traces）在實務上經常一起部署，但面試題通常只測 metrics + logs，traces 往往被跳過。加入 Tempo 能展示對整個 Grafana observability ecosystem 的熟悉程度——Alloy pipeline 配置、OTLP over gRPC 傳輸、Grafana datasource provisioning——而不只是照著預設路徑做。

**多覆蓋了哪些能力 / 少測了哪些**

| | 說明 |
|--|------|
| 多覆蓋 | Distributed tracing 架構（OTLP over gRPC、Tempo trace storage、Alloy pipeline）；Helm umbrella chart 組合多個 sub-chart；cluster label 注入讓多站點 trace 可區分；Kubernetes-native 部署整個 observability stack |
| 少測 | **Loki log aggregation**（題目明確要求，但本版本尚未完成）；多站點模擬腳本（`simulate/site-{1,2,3}/`）；Alert 規則（`SiteOffline`、`CriticalServiceDown`）；All-Sites Overview dashboard——這些是題目核心要求，目前是空缺，屬於實作進度問題，不是刻意取捨 |
