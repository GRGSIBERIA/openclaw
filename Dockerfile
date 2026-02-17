FROM node:22-bookworm

# ---- Versions (reproducibility) ----
ARG PNPM_VERSION=9.12.3
ARG BUN_VERSION=1.1.38

# Install Bun (fixed version) + enable pnpm via corepack (fixed version)
RUN set -eux; \
  curl -fsSL https://bun.sh/install | bash -s -- bun-v${BUN_VERSION}; \
  corepack enable; \
  corepack prepare pnpm@${PNPM_VERSION} --activate

ENV PATH="/root/.bun/bin:${PATH}"

WORKDIR /app

# Optional apt packages for custom runtime needs
ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN set -eux; \
  if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
  fi

# Copy only manifests first to maximize layer cache hit

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

# Optionally install Chromium and Xvfb for browser automation.
# Build with:
# docker build --build-arg OPENCLAW_INSTALL_BROWSER=1 ...
ARG OPENCLAW_INSTALL_BROWSER=""
RUN set -eux; \
  if [ -n "$OPENCLAW_INSTALL_BROWSER" ]; then \
  apt-get update; \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xvfb; \
  node /app/node_modules/playwright-core/cli.js install --with-deps chromium; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
fi

# Copy source and build
COPY . .

RUN pnpm build

# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Ensure non-root runtime can write app dir and its own home config dir
RUN set -eux; \
  mkdir -p /home/node/.openclaw; \
  chown -R node:node /app /home/node/.openclaw

# Security hardening: run as non-root
USER node

# Start gateway server with default config.
# Binds to loopback (127.0.0.1) by default for security.
#
# For container platforms requiring external health checks:
# 1) Set OPENCLAW_GATEWAY_TOKEN or OPENCLAW_GATEWAY_PASSWORD
# 2) Override CMD: ["node","openclaw.mjs","gateway","--allow-unconfigured","--bind","lan"]

CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]