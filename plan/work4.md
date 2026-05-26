# Ticket 4：Zero-Downtime Deploy with Database Migration — 需求分析

> 分析日期：2026-05-26  
> 策略：Docker Compose Blue-Green，以 **Traefik** 作為前置 reverse proxy

---

## 一、核心問題拆解

原始 deploy 腳本問題：
```bash
docker compose down   # 舊容器停止，port 3000 立即無法使用
docker compose up -d  # 新容器啟動需要 30~60 秒才通過 healthcheck
```
停機根因：**port 有空窗期**，沒有任何容器在接流量。

解法：讓新舊容器**同時存在**，Traefik 確認新容器健康後再切換，再關舊容器。

---

## 二、Traefik Blue-Green 架構

```
用戶請求
    │
    ▼
Traefik :80
    │
    │ 讀取 dynamic/app.yml（file provider）
    │
    ├──── 正常狀態：upstream = app:3000（藍）
    │
    └──── deploy 期間：upstream = app-new:3001（綠）
               ↑ deploy.sh 改寫 app.yml，Traefik 熱重載（毫秒）

    藍容器（app:3000）   綠容器（app-new:3001）
    [舊版 image]         [新版 image，啟動中/運行中]
```

### 為何選 Traefik（而非 nginx）

| 面向 | Traefik | nginx |
|------|---------|-------|
| 熱重載方式 | file provider 自動 watch，直接改 YAML | 需要 `nginx -s reload` 指令 |
| Blue-Green 切換 | 改一個 YAML 檔，Traefik 自己偵測 | 改 upstream 再 reload |
| Docker 整合 | 原生支援 label-based 或 file provider | 需要手動維護 upstream IP |
| 設定複雜度 | 略高（traefik.yml + dynamic/）| 較低（nginx.conf）|

Traefik 的 file provider 支援 **watch: true**，改 YAML 後無需任何 signal，Traefik 自動重新路由，這使切換邏輯從「發 signal 給 nginx」簡化為「寫一個 YAML 檔」。

---

## 三、Migration 執行順序（關鍵決策）

**結論：Pre-migration（先跑 migration，再切容器）**

```
老 app 持續服務
     │
     ├── migration container 啟動（連同一個 mongo）
     │     ├── Step 1: createIndex（MongoDB 7 hybrid，non-blocking）
     │     └── Step 2: backfill 新欄位（分批，不影響老 app）
     │
     ├── migration 成功 → 啟動 app-new → healthcheck → 切 Traefik → 停老 app
     └── migration 失敗 → EXIT（老 app 未受影響）
```

**理由：**

1. **Index build（MongoDB 7）**：Hybrid index build，build 過程不阻塞讀寫（只在開始和結束有極短鎖）。老 app 繼續服務。

2. **Backfill（新欄位）**：老 app 完全不讀新欄位，寫入時也不碰它。Backfill 可安全在老 app 運行時執行。

3. **新容器啟動時 DB 已就緒**：index 建好、資料 backfill 完成，新 app 不會因 DB 狀態不一致而啟動失敗。

4. **Migration 失敗 = 零影響**：老 app 從未停止，直接 exit 即可。

---

## 四、Migration 設計細節

### 4.1 Index Build

```javascript
// MongoDB 7: createIndex 預設 hybrid mode（non-blocking during build）
await db.collection("telemetry").createIndex(
  { deviceId: 1, timestamp: -1 },
  { name: "deviceId_timestamp_idx" }
);
```

2M 文件 index build 預估耗時：1~5 分鐘（視磁碟 I/O）。  
`deploy.sh` 必須等 migration container **完成**（exit 0）再繼續。

### 4.2 Backfill 設計

```javascript
const BATCH_SIZE = 1000;

while (true) {
  // 冪等：只處理沒有新欄位的文件
  const result = await db.collection("telemetry").updateMany(
    { newField: { $exists: false } },
    { $set: { newField: defaultValue } },
    { limit: BATCH_SIZE }
  );
  if (result.modifiedCount === 0) break;
  // 可加 sleep(10ms) 避免壓垮 mongo
}
```

**冪等性**：用 `$exists: false` 過濾，重跑不會覆蓋已存在的值。

---

## 五、Traefik 動態切換機制

### file provider 設定

`traefik.yml`（靜態配置）：
```yaml
providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true   # Traefik 自動偵測 YAML 變更
```

`dynamic/app.yml`（動態配置，deploy.sh 改寫這個）：
```yaml
http:
  routers:
    app:
      rule: "PathPrefix(`/`)"
      service: app-blue
  services:
    app-blue:
      loadBalancer:
        servers:
          - url: "http://app:3000"
```

切換時，`deploy.sh` 把 `app-blue` 換成 `app-green`，url 指向 `app-new:3001`：
```yaml
    app-green:
      loadBalancer:
        servers:
          - url: "http://app-new:3001"
```

Traefik 偵測到 file 變更後自動重新路由，**毫秒級，不中斷現有連線**。

---

## 六、完整 Deploy Flow

```
deploy.sh <new-image:tag>
│
├── 1. 初始化 log（timestamp, image tag, log file）
│
├── 2. docker pull <new-image>
│   └── 失敗 → EXIT（log error）
│
├── 3. 執行 migration container
│   ├── docker run --rm --network backend_default \
│   │     -e MONGO_URI=... <new-image> node migrate.js
│   ├── 等待 container 完成
│   └── exit code != 0 → log "Migration failed" → EXIT
│       （老 app 繼續服務，用戶無感知）
│
├── 4. 啟動 app-new 在 port 3001
│   └── docker run -d --name app-new \
│         --network backend_default \
│         -p 3001:3000 -e MONGO_URI=... <new-image>
│
├── 5. Healthcheck loop（最多 60 秒，每 3 秒 probe 一次）
│   ├── curl -sf http://localhost:3001/health
│   ├── 60s 內成功 → 繼續
│   └── 60s timeout → ROLLBACK
│       ├── docker stop app-new && docker rm app-new
│       ├── log "ROLLBACK: healthcheck timeout"
│       └── EXIT（Traefik 從未切換，老 app 繼續服務）
│
├── 6. 切換 Traefik upstream
│   ├── 更新 dynamic/app.yml：指向 app-new:3001
│   └── Traefik auto-detects（watch: true），不需要額外指令
│
├── 7. 停止老容器
│   └── docker stop app && docker rm app
│
├── 8. 重命名 app-new → app（下次 deploy 用）
│   └── docker rename app-new app
│
└── 9. 更新 dynamic/app.yml：service name 改回 app-blue，url 改 app:3000
    └── log "Deploy complete"
```

---

## 七、失敗模式分析

### 7.1 Index build 失敗

- Migration container exit != 0
- Deploy.sh 捕捉到，直接 exit
- 老 app 繼續服務，**零影響**
- MongoDB 自動清理 incomplete index（不會留 corrupt index）

### 7.2 Backfill 失敗（中途）

- Migration exit != 0
- 部分文件有新欄位，部分沒有
- 老 app 不讀新欄位，**無影響**
- 下次 deploy 重跑 migration，從 `$exists: false` 繼續（**冪等**）
- 不需要手動 rollback DB

### 7.3 Migration 成功，新容器 healthcheck 失敗（60s 內）

**這是最關鍵的失敗情境。**

- DB 狀態已改變（index 建好、資料 backfilled）
- 老 app 仍在 3000 port 運行
- `app-new` 在 60s 內未通過 healthcheck → stop & rm
- Traefik 的 `dynamic/app.yml` **從未被更新** → 老 upstream 繼續有效
- 對用戶：**完全無感知**

> 在 Blue-Green 策略中，「rollback」就是「不切換」。  
> 因為切換發生在健康確認之後，所以失敗就是什麼都沒發生。

### 7.4 切換後新容器才出問題（60s 視窗之後）

- 超出自動 rollback 範圍
- 需要手動重新部署老 image（`deploy.sh <old-image:tag>`）
- DB migration（additive）對老 app 無害，可安全降版
- 文件化：**migration 必須 backward compatible（additive only，不刪欄位，不改欄位語意）**

### 7.5 Traefik file provider 寫入失敗

- YAML 語法錯誤或寫入失敗
- Traefik 繼續使用舊的 dynamic config（有 watch 機制的容錯）
- 需要在寫入後驗證語法（用 `yq` 或簡單的 yaml lint）

---

## 八、需要實作的檔案

```
backend/
├── docker-compose.yaml          # 加入 traefik service
├── traefik/
│   ├── traefik.yml              # 靜態配置（entrypoints, providers）
│   └── dynamic/
│       └── app.yml              # 動態路由配置（deploy.sh 改寫這個）
├── migrate/
│   └── index.js                 # migration 邏輯（index build + backfill）
└── deploy.sh                    # 主部署腳本
```

---

## 九、README 說明大綱

1. **策略說明**：Blue-Green + Traefik
   - 為何 blue-green 而非 rolling：compose 無原生 rolling，手工實作即是 blue-green
   - 為何 Traefik：file provider + watch，切換不需要 reload signal，更乾淨
   - 為何不選 k3s：基礎建設 overhead 過大，評估時間限制

2. **Migration 順序說明**：Pre-migration 理由

3. **失敗模式表格**

| 失敗點 | 行為 | 用戶影響 | 恢復 |
|--------|------|----------|------|
| Migration 失敗 | 腳本 exit，不啟動新容器 | 無 | 修 migration 後重跑 |
| 新容器 healthcheck 失敗（60s 內）| 停 app-new，Traefik 未切換 | 無 | 修 image 後重跑 |
| Traefik config 寫入失敗 | 舊路由繼續有效 | 無 | 手動修 app.yml |
| 切換後新容器爆炸（60s 後）| 需手動 rollback | 有 | 重新 deploy 老 image |

4. **DB Rollback 的現實**：
   - Index：純優化，可 `dropIndex` 回滾，但通常不必要
   - Backfill（新欄位）：老 app 無視，無需移除
   - 原則：**migration 必須 additive-only**

---

## 十、預估工時

| 項目 | 時間 |
|------|------|
| Traefik 加進 docker-compose + traefik.yml + dynamic/app.yml | 45 min |
| migrate/index.js（index build + backfill + 錯誤處理）| 45 min |
| deploy.sh（logging + healthcheck loop + rollback + Traefik switch）| 60 min |
| README 說明 | 30 min |
| 測試（模擬 migration 失敗 / healthcheck 失敗）| 30 min |
| **合計** | **~3.5 小時** |
