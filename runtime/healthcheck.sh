#!/bin/bash
set -euo pipefail
curl -fsS --max-time 2 http://127.0.0.1:6080/ >/dev/null
curl -fsS --max-time 2 http://127.0.0.1:9222/json/version >/dev/null
# No model credentials are required for infrastructure readiness. The gateway's
# `healthy` field stays false until Codex is logged in; HTTP 200 is sufficient.
curl -fsS --max-time 2 "http://127.0.0.1:${AGENT37_GATEWAY_PORT:-3737}/v1/health" >/dev/null
docker info >/dev/null 2>&1
