# Multi-stage build to keep the final image small. Deploy anywhere that runs
# Docker: Fly.io, Railway, Render, Hugging Face Spaces, a VPS. The server listens
# on $PORT (default 3000) at /mcp behind an auth gate. See README → "Deploy".

# ─── build stage ───────────────────────────────────────────────────────────
FROM node:24-alpine AS builder
WORKDIR /app

# Copy manifests first so the npm install layer caches when only source changes.
COPY package.json package-lock.json* ./
RUN npm install

COPY tsconfig.json ./
COPY src ./src
RUN npx tsc && npm prune --omit=dev

# ─── runtime stage ─────────────────────────────────────────────────────────
FROM node:24-alpine AS runtime
WORKDIR /app

# Run as a non-root user (node:alpine ships a `node` user, uid 1000).
USER node

COPY --chown=node:node --from=builder /app/node_modules ./node_modules
COPY --chown=node:node --from=builder /app/dist ./dist
COPY --chown=node:node --from=builder /app/package.json ./

# Required at runtime, set via host secrets (`fly secrets set …`):
#   MCP_AUTH_TOKEN   random secret the phone + MCP clients send (openssl rand -hex 32)
#   AUTH_PASSWORD    password typed once when adding your MCP client connector
#   PUBLIC_URL       the server's public origin (OAuth issuer)
ENV MCP_TRANSPORT=http
ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/health || exit 1

CMD ["node", "dist/server.js"]
