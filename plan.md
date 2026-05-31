# Plan: Multi-Instance Backend with Unified Traefik

## 目標

`make dev-start <N>` 啟動第 N 個完全獨立的 backend stack，所有 instance 透過同一個 Traefik 入口路由，後端不直接 export port 到 host。

```
make dev-start 1   →  instance-1.localhost  + http://localhost  (INSTANCE=1 維持向下相容)
make dev-start 2   →  instance-2.localhost
make dev-start 3   →  instance-3.localhost
```

## 必須維持通過的測試

依 claude.md 要求，以下測試不得因本次改動而失敗：

| 測試 | 指令 |
|------|------|
| E2E | `make e2e-test` → `act push` |
| Migration | `make migration-test` → `act push` |
| Lint | `make lint` → `act push` |

---

## 現有限制分析（與原計劃的差異原因）

### 限制 1：e2e 測試直接呼叫 `docker compose`（無 project name）

`scripts/e2e/03-memory-check.sh` 和 `04-persistence.sh` 直接執行：

```bash
docker compose ps -q          # 使用預設 project = backend
docker compose down           # 使用預設 project = backend
docker compose up -d          # 使用預設 project = backend
```

**結論：INSTANCE=1 必須使用預設 project name（不傳 `-p`），保持 project = `backend`。**

### 限制 2：migration test 需要 Traefik 在 main compose 中

`scripts/migration/01-start-blue.sh`：

```bash
VERSION=$BLUE docker compose up -d --wait traefik mongo postgres redis
```

`04-persistence.sh` 重啟後也需要 Traefik 恢復（`docker compose up -d`）。

**結論：Traefik 不能移出 `docker-compose.yaml`，原計劃的 `docker-compose.traefik.yml` 方案不可行。**

### 限制 3：`deploy.sh` 依賴 file provider 做藍綠切換

`deploy.sh` 直接寫入 `traefik/dynamic/app.yml` 來切換上游，且使用 `backend_default` network 和容器名稱 `app`/`app-new`。

**結論：Traefik 必須同時保留 file provider（`deploy.sh` 相容）+ 新增 Docker provider（多 instance 探索）。不能單純換成 Docker provider。**

### 限制 4：`backend_default` network 名稱被硬編碼

`deploy.sh`、`01-start-blue.sh` 均寫死 `--network backend_default`。

**結論：INSTANCE=1 的 internal network 必須保持 `backend_default`。INSTANCE >= 2 使用 `backend-N`。**

---

## 網路拓樸

```
Host :80
  └── Traefik  (屬於 project=backend，即 INSTANCE=1 的 compose 管理)
        ├── backend_default network (INSTANCE=1 內部，file provider 路由)
        │     └── app-1 ← http://app:3000 (file provider catch-all for localhost)
        └── traefik_net (外部共享 network，Docker provider 路由)
              ├── app-1 ← Host(`instance-1.localhost`)
              ├── app-2 ← Host(`instance-2.localhost`)
              └── app-3 ← Host(`instance-3.localhost`)
```

- `traefik_net`：外部共享 Docker network，預先建立，所有 instance 的 `app` 加入
- `backend_default`：INSTANCE=1 的內部 network（保持原名，migration test 相容）
- `backend-N`：INSTANCE >= 2 的內部 network
- `app` 同時加入 `traefik_net` + 自己的 internal network
- DB/Redis/Collector/Alloy 只加入 internal network，不暴露給 Traefik

---

## Traefik 路由策略

| URL | Provider | 路由到 |
|-----|----------|--------|
| `http://localhost/*` | file provider | INSTANCE=1 的 app（`dynamic/app.yml` 保持不變） |
| `http://instance-1.localhost/*` | Docker provider | INSTANCE=1 的 app（label 路由） |
| `http://instance-2.localhost/*` | Docker provider | INSTANCE=2 的 app |
| `http://instance-3.localhost/*` | Docker provider | INSTANCE=3 的 app |

> **CI 測試都使用 `http://localhost`** → 走 file provider → INSTANCE=1 → 完全向下相容。

---

## 需要修改的檔案

### 1. `backend/traefik/traefik.yml` ← 修改

新增 Docker provider，同時保留 file provider：

```yaml
entryPoints:
  web:
    address: ":80"

providers:
  file:
    directory: /etc/traefik/dynamic   # 保留：deploy.sh 藍綠切換用
    watch: true
  docker:
    exposedByDefault: false
    network: traefik_net              # 新增：多 instance 探索用

api:
  insecure: false
```

---

### 2. `backend/docker-compose.yaml` ← 修改

#### `traefik` service：新增 `traefik_net` network
```yaml
traefik:
  # 原有設定不變
  networks:
    - backend        # 原有（需在 backend_default 才能路由到 app:3000，file provider 用）
    - traefik_net    # 新增：讓 Docker provider 能跨 instance 路由
```

#### `app` service：移除 ports + container_name，新增 labels + traefik_net
```yaml
app:
  image: backend:${VERSION:-dev}
  # 移除：container_name: app
  # 移除：ports: ["3000:3000"]
  expose:
    - "3000"
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.app-${INSTANCE:-1}.rule=Host(`instance-${INSTANCE:-1}.localhost`)"
    - "traefik.http.routers.app-${INSTANCE:-1}.entrypoints=web"
    - "traefik.http.services.app-${INSTANCE:-1}.loadbalancer.server.port=3000"
    - "traefik.docker.network=traefik_net"
  networks:
    - backend        # 內部網路（連 DB）
    - traefik_net    # 外部共享網路（讓 Traefik Docker provider 路由）
  # 其餘設定不變
```

#### `networks` section：加入 traefik_net，並讓 internal network 支援 INSTANCE 變數
```yaml
networks:
  backend:
    name: ${BACKEND_NET:-backend_default}   # INSTANCE=1 → backend_default；INSTANCE>=2 → backend-N
  traefik_net:
    name: traefik_net
    external: true                           # 由 Makefile 預先建立
```

#### volumes：INSTANCE >= 2 加 suffix 避免資料衝突
```yaml
mongo:
  volumes:
    - ${VOLUME_PATH:-/tmp}/mongo-data${INSTANCE_SUFFIX:-}:/data/db

postgres:
  volumes:
    - ${VOLUME_PATH:-/tmp}/postgres-data${INSTANCE_SUFFIX:-}:/var/lib/postgresql/data

redis:
  volumes:
    - ${VOLUME_PATH:-/tmp}/redis-data${INSTANCE_SUFFIX:-}:/data
```

> `INSTANCE_SUFFIX`：INSTANCE=1 為空（保持原路徑相容），INSTANCE=2 為 `-2`，以此類推。

---

### 3. `backend/Makefile` ← 修改

```makefile
INSTANCE ?= 1
VOLUME   ?= /tmp

# INSTANCE=1：使用預設 project（保持向下相容，e2e/migration tests 依賴此行為）
# INSTANCE>=2：使用獨立 project，獨立 internal network
ifeq ($(INSTANCE),1)
  COMPOSE      = docker compose
  BACKEND_NET  = backend_default
  INST_SUFFIX  =
else
  COMPOSE      = INSTANCE=$(INSTANCE) BACKEND_NET=backend-$(INSTANCE) \
                 INSTANCE_SUFFIX=-$(INSTANCE) docker compose -p backend-$(INSTANCE)
  BACKEND_NET  = backend-$(INSTANCE)
  INST_SUFFIX  = -$(INSTANCE)
endif

# 啟動用的服務清單（INSTANCE>=2 排除 traefik，避免 port 80 衝突）
ifeq ($(INSTANCE),1)
  SERVICES =
else
  SERVICES = app collector mongo postgres redis alloy
endif

.PHONY: ensure-traefik-net
ensure-traefik-net:
    docker network create traefik_net 2>/dev/null || true

.PHONY: dev-start
dev-start: ensure-traefik-net dev-stop image
    @set -a; [ -f .env ] && . ./.env; set +a; \
    VPATH=$${VOLUME_PATH:-$(VOLUME)}; \
    mkdir -p "$$VPATH/mongo-data$(INST_SUFFIX)" \
             "$$VPATH/postgres-data$(INST_SUFFIX)" \
             "$$VPATH/redis-data$(INST_SUFFIX)"
    $(COMPOSE) up -d $(SERVICES)
    $(COMPOSE) exec app node dist/seed.js

.PHONY: dev-stop
dev-stop:
    $(COMPOSE) down

.PHONY: dev-stop-all
dev-stop-all:
    @for i in 1 2 3 4 5; do \
        INSTANCE=$$i BACKEND_NET=backend-$$i INSTANCE_SUFFIX=-$$i \
        docker compose -p backend-$$i down 2>/dev/null || true; \
    done
    docker compose down 2>/dev/null || true

.PHONY: migration-test
migration-test: ensure-traefik-net
    @[ -f .env ] || { echo "No .env found — copying from .env.example"; cp .env.example .env; }
    @echo "=== Migration + deploy integration test ==="
    @set -e; \
    trap 'bash scripts/migration/cleanup.sh' EXIT; \
    bash scripts/migration/cleanup.sh; \
    bash scripts/migration/01-start-blue.sh; \
    bash scripts/migration/02-deploy-green.sh; \
    echo "PASS: migration-test complete"

# e2e-test 不需要修改，make dev-start（INSTANCE=1 預設）會建立 traefik_net
```

---

### 4. 根目錄 `Makefile` ← 修改

```makefile
# Positional arg support: make dev-start 2 → INSTANCE=2
INSTANCE := $(word 2,$(MAKECMDGOALS))
ifeq ($(INSTANCE),)
  INSTANCE := 1
endif

.PHONY: dev-start
dev-start:
    make -C backend dev-start INSTANCE=$(INSTANCE)

.PHONY: dev-stop
dev-stop:
    make -C backend dev-stop INSTANCE=$(INSTANCE)

# Absorb numeric targets so Make doesn't complain about "No rule to make target 2"
%:
    @:
```

---

### 5. `backend/scripts/migration/01-start-blue.sh` ← 修改（新增一行）

在 `docker compose up` 之前加入 `traefik_net` 建立（因 compose file 宣告 external network）：

```bash
# 新增：確保外部 network 存在
docker network create traefik_net 2>/dev/null || true

echo "--- Start infrastructure (traefik + databases) ---"
VERSION=$BLUE docker compose up -d --wait traefik mongo postgres redis
```

> `cleanup.sh` 不需修改：`docker compose down` 不會刪除外部 network（`traefik_net`），符合預期。

---

## 不需修改的檔案

| 檔案 | 原因 |
|------|------|
| `traefik/dynamic/app.yml` | 保持原有 `PathPrefix(/)` → `app:3000`，CI 測試的 `http://localhost` catch-all |
| `deploy.sh` | 使用 file provider + `backend_default` network，INSTANCE=1 行為不變 |
| `scripts/e2e/02-api-smoke.sh` | `http://localhost` 仍由 file provider 路由 |
| `scripts/e2e/03-memory-check.sh` | `docker compose ps -q` 使用預設 project，INSTANCE=1 ✓ |
| `scripts/e2e/04-persistence.sh` | `docker compose up -d` 重啟，Traefik 會隨 INSTANCE=1 的 compose 重啟 ✓ |
| `scripts/migration/02-deploy-green.sh` | `deploy.sh` 行為不變 |
| `scripts/migration/cleanup.sh` | `docker compose down` 清理預設 project，`traefik_net` 為 external，不會被刪 |
| `.github/workflows/*.yml` | CI 不傳 INSTANCE，預設 INSTANCE=1 ✓ |

---

## 使用流程

```bash
# Traefik_net 由 dev-start 自動建立，無需手動步驟

# 啟動各 instance（各自獨立 DB）
make dev-start 1   # http://localhost 或 http://instance-1.localhost
make dev-start 2   # http://instance-2.localhost
make dev-start 3   # http://instance-3.localhost

# 停止特定 instance
make dev-stop 2

# 停止全部
make -C backend dev-stop-all

# CI 測試（不傳 INSTANCE，預設行為不變）
make e2e-test
make migration-test
make lint
```

本機 curl 測試：
```bash
curl http://localhost/health                              # INSTANCE=1，file provider
curl -H "Host: instance-2.localhost" http://localhost/health  # INSTANCE=2，Docker provider
# 或加入 /etc/hosts: 127.0.0.1 instance-2.localhost
curl http://instance-2.localhost/health
```

---

## 注意事項

1. **`container_name: app` 移除後的 `deploy.sh` 相容性**：`deploy.sh` 做 `docker rm -f app`，但 blue 容器是由 `docker run --name app` 啟動（非 compose 管理），不受 container_name 影響。Traefik file config 用 `http://app:3000` 透過 Docker DNS service alias 解析，與 container_name 無關。✓

2. **INSTANCE=1 的 app 在 traefik_net 上的 Docker provider 路由**：label 設 `Host(instance-1.localhost)`，與 file provider 的 `PathPrefix(/)` catch-all 並存，兩者不衝突。

3. **Alloy 重複採集**：多個 instance 各自有 Alloy container，都 mount `/var/run/docker.sock`，會各自採集全部容器 metrics。Dev 環境可接受，如需避免，可在 INSTANCE >= 2 的 SERVICES 清單中移除 `alloy`。

4. **資源消耗**：每個 instance 需約 3–4 GB RAM（含 DB）。建議只起需要的 instance。
