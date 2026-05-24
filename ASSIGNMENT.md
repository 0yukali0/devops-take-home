# DevOps / SRE Engineer 作業說明

![cover](./cover.png)

## 背景

這是一個模擬的 EMS（能源管理系統）邊緣站點。它從能源設備（逆變器、電池、電表等）收集遙測資料，存入 MongoDB，並透過 API 提供給前端 dashboard 使用。

目前這個 stack 是由一個「只想讓它能跑就好」的開發者建置的。它可以運行，但完全不適合 production 環境。

你的任務是把它變成可靠的、可維運的 production 服務。

## 啟動方式

```bash
docker compose up -d --build
# 等服務啟動後，seed 資料:
docker compose exec app node dist/seed.js
# API 在 http://localhost:3000
# 資料收集器會每 10 秒自動寫入新的遙測資料
```

如果想在本機開發（不透過 Docker）：

```bash
pnpm install
pnpm dev            # 用 tsx watch + pino-pretty 跑 API
pnpm dev:collector  # 另外跑資料收集器
pnpm seed           # 寫入約 2M 筆遙測資料到 mongo
```

### API 端點

- `GET /health` — 健康檢查
- `GET /api/devices` — 所有設備列表
- `GET /api/devices/:deviceId/telemetry?from=&to=&limit=` — 某設備的遙測資料
- `GET /api/telemetry/latest` — 所有設備的最新資料（dashboard 用）
- `POST /api/telemetry` — 寫入一筆遙測資料
- `GET /api/dashboards` — 所有 dashboard 設定（Postgres）
- `POST /api/dashboards` — 建立 dashboard 設定
- `GET /api/cache/:key` — Redis 快取查詢

## Stack

- **App**: TypeScript / Hono on Node.js — API server（esbuild 打包、tsx 跑 dev）
- **Collector**: TypeScript / Node.js — 模擬設備資料收集器，每 10 秒寫入資料
- **MongoDB 7**: 主要資料庫，儲存設備資訊和遙測資料
- **PostgreSQL 16**: 儲存 dashboard 設定和內部工具資料
- **Redis 7**: Session 和快取
- Logging: pino（dev 環境配 pino-pretty）
- Validation: zod
- Package manager: pnpm

## 情境假設

- 這個 stack 跑在客戶現場的一台 Linux 主機上（8GB RAM / 50GB disk）
- 你只能透過 SSH 存取這台主機
- 我們有 12 個這樣的站點，每個站點的設定不同（domain、DB 密碼、設備數量）

---

## Tickets

以下是 7 張 tickets。你不需要全部做完——選你認為最重要的做好。

**必填的 tickets：**
- **Ticket 3（Central multi-site observability platform）**——這張最能展現你的觀測性架構能力，也最容易讓我們直接看到成果
- **Ticket 7（Prioritization and strategy）**——不管你做了哪些 tickets，這張一定要寫

其他 tickets 自由選做。我們寧可看到 2 張 ticket 做得扎實，也不要 5 張都是半成品。

### 你可以修改題目

如果某張 ticket 你覺得換一個方式做會更好，可以自己改題目。兩種我們接受的理由：

1. **更貼近這個職位實際的需求**——你覺得原本的題目沒抓到我們真正在意的東西，或者有更實用的解法
2. **更能展現你的能力**——原本題目蓋不到你的強項，換個方式能讓我們看到更完整的你

不管是哪種，請在 README 裡面寫清楚：

1. 你怎麼改的（原本要做什麼、你改成做什麼）
2. 為什麼改（是為了更貼近職位需求、還是為了展現某個能力，還是兩者都有）
3. 你的版本跟原本相比，多覆蓋了哪些原本想測的能力，又少測了哪些

**舉例：**
- Ticket 3 我們預期是 Prometheus + Grafana + Loki，但如果你想用別的方案來展示對觀測性架構的理解，可以——說明你的取捨。
- Ticket 5（GitOps）你可能覺得 ArgoCD 太重，想用更輕量的 git webhook + script，可以——說明你的判斷依據。
- Ticket 6（Claude Code 維運交接）你可能想改成寫一份完整的 runbook 給人類同事看，也可以——說明你為什麼覺得這比 AI 交接更實用。
- 你也可以加一張我們沒列的 ticket，如果它能展現某個我們應該想知道的能力。

Ticket 3 和 Ticket 7 還是必填的——實作方式可以改，主題不變。

**為什麼我們允許這樣：** 工作上有時候需求不夠清楚，或實際上有更好的做法。一個好的工程師會主動 push back、提出更適合的方案，而不是埋頭做不適合的事。我們想看你的判斷力和你怎麼介紹自己的能力——這兩個都比照本宣科地做完題目更重要。

---

### Ticket 1: Database misconfiguration

MongoDB 的 WiredTiger cache 設為 4GB，但主機只有 8GB RAM——要跟 App、Postgres、Redis 和 OS 一起分。主機正在 swap。

但這不是單純改一個設定的問題。這個 stack 還有以下幾個相關問題：

- No memory limits on any container
- MongoDB is running with no authentication — anyone can connect
- No volume mounts — data disappears when containers restart
- Postgres has `shared_buffers` at the default 128MB (too low) while MongoDB has too much

**我們想看到的（請寫在 README）：**
- 針對 8GB 主機調整 MongoDB 和 Postgres 的記憶體設定。展示你的計算——你怎麼分配記憶體預算？
- 每個 service 加上 Docker memory limit
- 開啟 MongoDB 認證
- 修好 volume mount，確保資料持久化
- 說明如果某個 service 超過它的記憶體上限會發生什麼

---

### Ticket 2: Site disaster recovery backup pipeline

一台站點主機掛了——硬碟壞了、需要換機器、隨便什麼原因。目前完全沒有備份策略，整個站點的資料都會遺失。

每個站點跑著以下這些東西：
- **MongoDB** (~10GB, grows ~200MB/day) — primary app database
- **Postgres** (~5GB, grows slowly) — Grafana and internal tooling
- **Redis** — session store and cache
- **Docker volumes** — uploaded assets, SSL certs, Grafana dashboards/config
- **App config** — `.env` files, docker-compose overrides

Constraints:
- Backups must go to S3
- Bandwidth varies per site (10Mbps to 100Mbps)
- A site might go offline for up to 72 hours without losing data
- Backups must be encrypted at rest
- 12 sites — must be automated and low-maintenance

**Part A: Design — 設計（請寫在 README）**
- 什麼東西要備份？多久一次？用什麼工具？
- 不是所有東西都需要相同策略——說明你的分級方式
- 全量備份 vs 增量備份：每種資料類型的做法？
- 保留政策和 S3 儲存成本管理
- 怎麼監控 12 個站點的備份是否正常運作？

**Part B: Implement a prototype**
- Add a backup agent container to the docker-compose stack
- It should back up MongoDB, Postgres, and a designated Docker volume to S3
- First run: full backup. Subsequent runs: incremental where possible
- Include a `restore.sh` that rebuilds the site from backup and verifies data integrity

**Part C: 困難問題（請寫在 README）**
- 什麼東西你選擇「不」備份？為什麼？
- Redis：要備份嗎？不備份會丟失什麼？
- 一個站點離線了 3 天——你的復原流程是什麼？可能出什麼問題？
- 如果 MongoDB 的 oplog 在你同步之前就被覆蓋了（wrap），會怎樣？怎麼防止？

---

### Ticket 3: Central multi-site observability platform (MANDATORY)

我們有 12 個邊緣站點，每個都跑相同的 app stack。目前完全沒有可見度——東西壞了都是客戶告訴我們才知道。

建置一個**中央監控服務**，讓多個邊緣站點把資料推送過來。邊緣站點應該盡量輕量（遙測收集用最少資源）。重的工作——儲存、dashboard、告警——在中央處理。

**starter setup 會模擬 3 個站點作為獨立的 docker-compose stack。** 你的任務是建置中央平台並設定每個站點向它回報。

**Requirements:**
- Each site pushes metrics and logs to the central platform (not the other way around — the central platform can't reach into sites; some networks don't accept inbound connections)
- Central dashboard with a single-pane view of all sites: which are healthy, which need attention
- Drill-down to a single site: container status, DB health, memory/disk usage
- At least one alert: a site stops reporting (went offline) or a critical service is down
- The central platform must gracefully handle a site going offline — no broken dashboards or false alerts

**推薦的 stack：** 我們在 production 環境用的是 **Grafana stack**（Grafana + Prometheus + Loki + Alloy / Promtail），希望你的解法用這個。如果你有強烈的理由想用別的方案，請參考開頭的「你可以修改題目」一節，並在 README 說明你的理由。

**我們想看到的（請寫在 README）：**
- 什麼跑在邊緣（collector/agent），什麼跑在中央（儲存、查詢、dashboard）
- 你怎麼讓邊緣的資源佔用盡量小——這些是資源有限的主機
- 這怎麼擴展到 12 個站點，然後 50 個站點
- 站點離線幾天後重新上線怎麼辦——它會回補資料，還是你接受空白？

**README 還要包含：**
- 架構圖（ASCII / 文字都可以）
- 每一層（收集、傳輸、儲存、視覺化、告警）你選了什麼，為什麼
- 擴展到 50 個站點時，什麼會先爆掉？

---

### Ticket 4: Zero-downtime deploy with database migration

目前的部署腳本是：
```bash
docker compose down
docker compose up -d
```

每次部署都會造成 30~60 秒的停機。新版本的 app 還需要：
- A new MongoDB index on a collection with 2M documents
- A migration script that adds a new field and backfills data

Write a `deploy.sh` that:
- Pulls the new image
- Runs the migration (build index + backfill) without blocking the running app
- Swaps to the new container with zero or near-zero downtime
- Automatically rolls back if the new container's healthcheck fails within 60 seconds
- Logs what happened (success, rollback, errors) for post-deploy review

**選擇性：Kubernetes 變體。** 如果你想展示 Kubernetes 能力，可以改用 **k3s** 來解這題——把 stack 的相關部分轉成 Deployment + Service + readiness/liveness probes，用 Job 或 initContainer 跑 migration，讓平台處理 rollout + rollback。我們未來有可能往 k3s 方向走，所以這個訊號對我們很有用。

如果你選這條路，兩點提醒：
- starter stack 的其他部分還是 docker-compose。只把 app 轉成 K8s、資料庫繼續留在 compose 是 OK 的——你不需要把整個 stack 都 k8s 化。請評估好你的時間。
- `strategy: RollingUpdate` + readiness probe 只是起點，不是答案。我們想看到你對以下問題的思考：migration 的執行順序（誰先誰後？）、舊 pod 已經消失但新 pod 的 healthcheck 失敗時會發生什麼、index build 在 2M 筆文件上失敗時你怎麼處理、DB state 已經改變後 rollback 實際上怎麼運作。

**請在 README 說明：** 你的策略是什麼（compose rolling、blue-green、k3s Deployment、其他），為什麼選這個。失敗模式有哪些——如果 migration 成功但新 app container 失敗，會怎樣？如果你選了 k3s 路線，請額外說明你對 K8s rollout 原語以外的決策（migration job 何時執行、rollback 如何處理已變更的 DB state 等）。

---

### Ticket 5: GitOps site configuration and deployment

我們有 12 個站點，每個站點的設定不同（image tag、domain、DB 密碼、feature flag）。目前更新站點的方式是 SSH 進去手動改檔案。

設計並實作一個 GitOps 工作流程：
- Each site's config lives in a git repo
- Pushing a config change automatically triggers a deploy to that site
- Rolling back a site = reverting a commit
- Sensitive values (DB passwords, API keys) can't be stored in plaintext in the repo

**Implement a prototype:**
- A config repo organized per-site (directories or files)
- A mechanism to detect changes and deploy to the correct site (GitHub Actions, a watcher script, ArgoCD/Flux, anything — your choice)
- Demonstrate: change a config value, push, and the running stack picks it up
- Demonstrate: revert the commit, and the site rolls back

**請在 README 說明：**
- 你為什麼選這個方案而不是其他方案？
- 你怎麼處理 secrets？
- 部署到一半失敗怎麼辦——一個站點更新了、下一個沒有？
- 怎麼防止有人不小心把壞的設定 push 到全部 12 個站點？

---

### Ticket 6: AI-assisted operations handoff

你要去放假兩週。你的同事是一個全端開發者，不太熟悉 infra。他有 Claude Code 可以用。

讓你的同事可以打開這個 repo、開一個 Claude Code session，然後靠跟 Claude 對話來處理日常維運——不需要理解底層的指令或基礎架構細節。

Claude should be able to help them:
- Check the health of all sites
- Deploy a new version to a specific site
- Roll back a failed deploy
- Check and restore backups
- Investigate why a site is down
- View monitoring dashboards

**怎麼達成由你決定。** CLAUDE.md、custom skills、hooks、scripts、MCP servers、prompt files，或任何組合——選你認為最適合的方式，並在 README 說明為什麼。

**Requirements:**
- A non-DevOps person + Claude should be able to handle the top 5 most common operational tasks without calling you
- Claude should know what's dangerous and warn accordingly
- If Claude doesn't know how to handle something, it should say so clearly rather than guess

**我們會怎麼評估：**
- 我們會在 Claude Code 裡打開你的 repo，嘗試執行上面列的那些操作
- 評分標準：Claude 知道該做什麼嗎？指示是否清楚到它不會亂猜步驟？是否安全地處理邊界情況？

**請在 README 說明：**
- 你選了什麼方式，為什麼？
- 你涵蓋了哪些場景？
- 你刻意沒涵蓋什麼，為什麼？
- 這個方式的限制在哪——哪些地方 Claude 還是需要人？

---

### Ticket 7: Prioritization and multi-site strategy (README only, MANDATORY)

你第一天上班就收到以上 6 張 tickets。你這週不可能全部做完。

1. 你會依什麼順序處理？為什麼？
2. 有哪些 ticket 你會反推回去或要求更多資訊？你會問什麼？
3. 如果這個 stack 部署在 12 個客戶站點，各有不同的 domain、不同的 DB 密碼、不同的網路環境（有的可以從外面連進去、有的不行）——你會先建什麼來讓日子好過一點？

---

## 規則

- 你不需要做完全部 7 張 ticket——選你認為最重要的做好
- **Ticket 3（central multi-site observability）和 Ticket 7（prioritization）是必填的**
- 其他 tickets 自由選做 2~3 張
- 我們寧可看到少數幾張做好的，不要全部都做一半的
- README 要包含：你做了什麼、跳過了什麼、為什麼這樣排優先順序、如果多一週你會先做什麼
- **AI 透明度：** 你用了哪些 AI 工具、哪些部分主要靠 AI、有沒有什麼有趣的 AI 互動。我們也用 AI——我們想看你怎麼用，不是看你假裝沒用。
- **時間：** 建議大概抓 3 天左右，不是硬性規定。

## 繳交方式

- GitHub repo（public 或 invite 我們）
- README 寫好
- 如果有 deploy 也歡迎附連結，沒有也沒關係

## 有問題歡迎問

題目刻意留了一些模糊空間。遇到不確定的地方可以自己做判斷（並在 README 說明），也可以直接問我釐清需求。怎麼釐清需求、什麼時候該問、什麼時候該自己決定，這本身也是我們在看的。
