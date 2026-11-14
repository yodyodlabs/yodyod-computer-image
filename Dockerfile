# syntax=docker/dockerfile:1.7
FROM node:24.22.3-bookworm-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54 AS node-runtime

FROM node-runtime AS gateway-build
ARG GATEWAY_VERSION=v0.18.1
ARG GATEWAY_COMMIT=56286fb2bda22135c5f3c74511db78e0edcf94fa
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates rsync \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "$GATEWAY_VERSION" \
      https://github.com/agent37-platform/gateway.git /gateway \
    && test "$(git -C /gateway rev-parse HEAD)" = "$GATEWAY_COMMIT"
WORKDIR /gateway
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=optional --no-audit --no-fund && npm run build \
    && npm prune --omit=dev --omit=optional --no-audit --no-fund

# Ubuntu 26.04's glycin icon loaders require nested bubblewrap namespaces,
# unavailable on Standard/gVisor. Use the maintained 24.04 LTS desktop stack.
FROM ubuntu:24.04@sha256:2198e4c65076e9cb0b3d695219df667c0e3b0072da64ca3c2648aca17dcecaf5

LABEL org.opencontainers.image.title="YodYod Computer" \
      org.opencontainers.image.description="Agent37 Ubuntu desktop with Codex, a shared visible Chrome, browser and desktop MCP tools" \
      org.opencontainers.image.source="https://github.com/yodyodlabs/yodyod-computer-image"

USER root
ARG DEBIAN_FRONTEND=noninteractive
ENV HOME=/root
# Match Agent37's desktop components without its VM-only Docker daemon.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git iproute2 less sudo tini \
      xfce4-session xfwm4 xfce4-panel xfdesktop4 xfce4-settings xfce4-terminal \
      thunar xfce4-appfinder exo-utils dbus-x11 \
      tigervnc-standalone-server novnc websockify x11-utils fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html \
    && printf '{"autoconnect":true,"resize":"remote"}\n' > /usr/share/novnc/defaults.json
# Ubuntu's Firefox package is a Snap stub; use Mozilla's signed .deb repository.
RUN install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
       -o /etc/apt/keyrings/packages.mozilla.org.asc \
    && echo 'deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main' \
       > /etc/apt/sources.list.d/mozilla.list \
    && printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' > /etc/apt/preferences.d/mozilla \
    && apt-get update && apt-get install -y --no-install-recommends firefox \
    && rm -rf /var/lib/apt/lists/*
# Keep baked software outside /root: Agent37 mounts the durable home over it.
COPY --from=node-runtime /usr/local/ /usr/local/
COPY --from=ghcr.io/astral-sh/uv:0.13.5@sha256:32a7bb39b496babbd997b0a39a4d66c126bdaf5661b302bf6f06abda8deca6ff /uv /uvx /usr/local/bin/
ENV UV_PYTHON_INSTALL_DIR=/opt/python \
    UV_PYTHON_BIN_DIR=/usr/local/bin \
    UV_LINK_MODE=copy \
    PATH=/opt/yodyod/browser-use/.venv/bin:/opt/yodyod/tools/node_modules/.bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DISPLAY=:1 \
    LANG=C.UTF-8 \
    CODEX_BIN=/opt/yodyod/tools/node_modules/.bin/codex \
    GATEWAY_DEFAULT_AGENT=codex \
    GATEWAY_WORKSPACE_DIR=/root/workspace \
    AGENT37_GATEWAY_HOME=/root/.agent37-gateway \
    BU_NAME=yodyod \
    BU_CDP_URL=http://127.0.0.1:9222 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential pkg-config python3 python3-venv python3-pip \
      jq ripgrep rsync unzip zip xz-utils wget gnupg \
      procps lsof iputils-ping dnsutils openssh-client \
      vim nano ffmpeg xdotool xclip scrot fonts-noto-cjk fonts-liberation \
    && rm -rf /var/lib/apt/lists/*
# Ubuntu's chromium package is a Snap stub. Install Google's signed .deb instead.
# Chrome stable intentionally receives security updates on each image rebuild.
RUN install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
       -o /etc/apt/keyrings/google-chrome.asc \
    && echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.asc] https://dl.google.com/linux/chrome/deb/ stable main' \
       > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/root/.cache/uv \
    uv python install 3.12.12 --default

WORKDIR /opt/yodyod/tools
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev --no-audit --no-fund \
    && npm install --global --no-audit --no-fund pnpm@10.22.0 \
    && codex --version
WORKDIR /opt/yodyod/browser-use
COPY browser-use/pyproject.toml browser-use/uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --python 3.12.12 \
    && browser-use --version

COPY --from=gateway-build /gateway/dist/ /opt/yodyod/gateway/dist/
COPY --from=gateway-build /gateway/node_modules/ /opt/yodyod/gateway/node_modules/
COPY --from=gateway-build /gateway/package.json /gateway/LICENSE /opt/yodyod/gateway/
# Tool/test changes should not invalidate the much larger dependency layers.
COPY tools/ /opt/yodyod/tools/tools/
COPY tests/ /opt/yodyod/tools/tests/
COPY config/ /opt/yodyod/config/
COPY runtime/ /opt/yodyod/runtime/
COPY scripts/ /opt/yodyod/scripts/
RUN chmod 0755 /opt/yodyod/runtime/*.sh /opt/yodyod/scripts/*.sh \
    && ln -s /opt/yodyod/runtime/browser.sh /usr/local/bin/yodyod-browser \
    && node --check /opt/yodyod/tools/tools/desktop-mcp.mjs \
    && python3 -m compileall -q /opt/yodyod/runtime

EXPOSE 3737 6080
# Agent37 mounts an initially empty disk over /root. Its VM launcher changes to
# this directory before exec, so a masked /root/workspace prevents even tini/sh
# from starting. Bootstrap creates the workspace only after entrypoint starts.
WORKDIR /
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
  CMD /opt/yodyod/runtime/healthcheck.sh
# The supervisor forwards TERM to each service; browser.sh must close Chrome
# through CDP before its processes are killed so cookies/profile writes flush.
ENTRYPOINT ["tini", "-s", "--", "/opt/yodyod/runtime/entrypoint.sh"]
