#!/bin/bash
set -euo pipefail
curl -fsS --max-time 2 http://127.0.0.1:6080/ >/dev/null
# Chrome can be intentionally closed while the desktop remains healthy.
DISPLAY=:1 xprop -root _NET_SUPPORTING_WM_CHECK | grep -q 'window id #'
# No model credentials are required for infrastructure readiness. The gateway's
# `healthy` field stays false until Codex is logged in; HTTP 200 is sufficient.
curl -fsS --max-time 2 "http://127.0.0.1:${AGENT37_GATEWAY_PORT:-3737}/v1/health" >/dev/null
