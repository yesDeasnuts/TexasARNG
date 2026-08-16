# syntax=docker/dockerfile:1
#
# Single image that builds the React SPA and serves it from the Express API.
# One process, one port — works unchanged on Fly, Render, Railway or a VPS.

# ---------------------------------------------------------------- client ----
FROM node:22-bookworm-slim AS client
WORKDIR /app/client
COPY client/package*.json ./
RUN npm ci
COPY client/ ./
RUN npm run build

# ------------------------------------------------------- server deps --------
# better-sqlite3 and sharp are native modules; build them in a stage that has a
# toolchain, then copy only the resulting node_modules into the runtime image.
FROM node:22-bookworm-slim AS deps
WORKDIR /app/server
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ \
 && rm -rf /var/lib/apt/lists/*
COPY server/package*.json ./
RUN npm ci --omit=dev

# --------------------------------------------------------------- runtime ----
FROM node:22-bookworm-slim AS runtime
ENV NODE_ENV=production \
    PORT=8080 \
    HOST=0.0.0.0 \
    DATA_DIR=/data \
    DB_FILE=/data/texasarng.db \
    UPLOAD_DIR=/data/uploads

RUN apt-get update \
 && apt-get install -y --no-install-recommends tini curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=deps   /app/server/node_modules ./server/node_modules
COPY server/package*.json ./server/
COPY server/src        ./server/src
COPY server/scripts    ./server/scripts
COPY server/test       ./server/test
COPY --from=client /app/client/dist ./client/dist
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# /data is the persistent volume: SQLite database + uploaded badge artwork.
RUN mkdir -p /data/uploads && chown -R node:node /data /app
USER node
VOLUME ["/data"]
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=4s --start-period=15s --retries=3 \
  CMD curl -fsS http://127.0.0.1:${PORT}/api/health || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["node", "server/src/index.js"]
