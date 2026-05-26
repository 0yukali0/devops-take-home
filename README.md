# DevOps Take-Home

## Summary

| 優先序 | Ticket | 名稱 | 狀態 | 預估工時 |
|--------|--------|------|------|---------|
| 1 | T4 | Zero-Downtime Deploy | ✅ 完成 | 3h |
| 1 | T2 | Backup Pipeline | — 跳過（需討論） | — |
| 2 | T3 | Central Multi-Site Observability | 🔄 進行中 | 8–10h |
| 2 | T1 | Database Misconfiguration | ⬜ 未完成 | 2h |
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

## Ticket 1：Database Misconfiguration ⬜

修正 `docker-compose.yaml` 的記憶體、認證、資料持久化問題。

### 待修正問題

| 位置 | 問題 |
|------|------|
| `docker-compose.yaml:46` | MongoDB `--wiredTigerCacheSizeGB 4`（主機 8GB 僅此服務就用掉 4GB）|
| `docker-compose.yaml` | MongoDB 無認證（`--auth` 未開啟）|
| `docker-compose.yaml` | 所有服務無 volume mount，重啟後資料消失 |
| `docker-compose.yaml` | 所有服務無 memory limit |

### 記憶體預算（8GB 主機）

| 服務 | memory limit | 備註 |
|------|-------------|------|
| app (Node.js) | 512m | — |
| collector (Node.js) | 256m | — |
| MongoDB | 2g | wiredTigerCacheSizeGB 1.5 |
| PostgreSQL | 1g | shared_buffers=512MB |
| Redis | 512m | maxmemory 256mb |
| OS + headroom | ~3.7g | — |

### 待完成

- [ ] MongoDB：調整 cache 大小、開啟 `--auth`、加入 volume
- [ ] PostgreSQL：`shared_buffers=512MB`、加入 volume
- [ ] Redis：`--maxmemory 256mb --maxmemory-policy allkeys-lru`、加入 volume
- [ ] 所有服務加入 `deploy.resources.limits.memory`
- [ ] 密碼改用 `.env` 管理（加入 `.gitignore`）

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
