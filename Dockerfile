# =============================================================================
# zero-waste-backend — production image
# Multi-stage: deps → runtime. Final image runs as non-root with a healthcheck.
# =============================================================================

# ---------- 1. Install production deps in a clean layer ----------
FROM node:20-alpine AS deps
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev && npm cache clean --force

# ---------- 2. Runtime ----------
FROM node:20-alpine AS runtime
WORKDIR /app

# wget is needed for the HEALTHCHECK; tini gives us proper PID-1 signal handling
RUN apk add --no-cache tini wget && \
    addgroup -S app && adduser -S app -G app

ENV NODE_ENV=production \
    PORT=5000

COPY --from=deps /app/node_modules ./node_modules
COPY --chown=app:app package.json ./
COPY --chown=app:app server.js ./
COPY --chown=app:app src ./src

USER app
EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:5000/health || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "server.js"]
