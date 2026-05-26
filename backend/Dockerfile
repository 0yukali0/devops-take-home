# syntax=docker/dockerfile:1
FROM node:22.11.0-alpine3.20 AS base

# build stage
FROM base AS builder
WORKDIR /app

RUN npm i -g corepack@latest && \
    corepack enable pnpm && \
    corepack use pnpm@9.15.4

RUN --mount=type=cache,sharing=locked,mode=0777,target=/root/.local/share/pnpm/store,id=pnpm-store \
    --mount=type=bind,target=package.json,src=package.json \
    --mount=type=bind,target=pnpm-lock.yaml,src=pnpm-lock.yaml \
    pnpm install --frozen-lockfile

RUN --mount=type=bind,target=package.json,src=package.json \
    --mount=type=bind,target=tsconfig.json,src=tsconfig.json \
    --mount=type=bind,target=src,src=src \
    --mount=type=bind,target=migrate,src=migrate \
    pnpm build && \
    node_modules/.bin/esbuild migrate/index.ts --bundle --platform=node --outdir=dist/migrate --format=cjs

# production stage
FROM base AS runner
WORKDIR /app

ENV NODE_OPTIONS="--dns-result-order=ipv4first"

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 edge

COPY --chown=edge:nodejs package.json ./
COPY --from=builder --chown=edge:nodejs /app/dist ./dist

USER edge

CMD ["node", "dist/index.js"]
