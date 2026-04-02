FROM node:22-bookworm AS build

WORKDIR /app

# Install git
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Clone the repo directly
RUN git clone --depth 1 https://github.com/mhalder/qdrant-mcp-server.git .

# Install dependencies and build
RUN npm ci
RUN npm run build
RUN npm prune --omit=dev

# ---- runtime stage ----

FROM node:22-bookworm-slim AS runtime

WORKDIR /app
ENV NODE_ENV=production

# Copy built app
COPY --from=build /app/package*.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/build ./build

EXPOSE 3000

CMD ["node", "build/index.js"]
