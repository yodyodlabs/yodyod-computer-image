#!/bin/bash
set -euo pipefail

log() { printf '%s [yodyod] %s\n' "$(date -u +'%FT%TZ')" "$*" >&2; }
export HOME="${HOME:-/root}"
export DISPLAY=:1
export GATEWAY_WORKSPACE_DIR="${GATEWAY_WORKSPACE_DIR:-$HOME/workspace}"
export AGENT37_GATEWAY_HOME="${AGENT37_GATEWAY_HOME:-$HOME/.agent37-gateway}"
export GATEWAY_DEFAULT_AGENT=codex
export CODEX_BIN=/opt/yodyod/tools/node_modules/.bin/codex
export PORT="${AGENT37_GATEWAY_PORT:-3737}"
export HOST=0.0.0.0
export NODE_ENV=production

python3 /opt/yodyod/runtime/bootstrap.py
mkdir -p "$GATEWAY_WORKSPACE_DIR" "$AGENT37_GATEWAY_HOME" "$HOME/.config/yodyod/chrome"

# Authenticate at runtime only. A persisted ChatGPT login takes precedence.
key="${OPENAI_API_KEY:-${CODEX_API_KEY:-}}"
if [[ -n "$key" ]] && ! "$CODEX_BIN" login status >/dev/null 2>&1; then
  if printf '%s\n' "$key" | "$CODEX_BIN" login --with-api-key >/dev/null 2>&1; then
    log 'Codex API-key login configured.'
  else
    log 'Codex login failed; use codex login --device-auth in the terminal.'
  fi
fi
unset key

pids=()
browser_pid=""
cleanup() {
  trap - TERM INT
  # Keep the X server alive while Chrome flushes its persistent profile.
  if [[ -n "$browser_pid" ]]; then
    kill "$browser_pid" 2>/dev/null || true
    wait "$browser_pid" 2>/dev/null || true
  fi
  if ((${#pids[@]})); then
    kill "${pids[@]}" 2>/dev/null || true
    wait "${pids[@]}" 2>/dev/null || true
  fi
}
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 130' INT

# Standard/gVisor instances cannot run dockerd.
/opt/yodyod/runtime/desktop.sh &
pids+=("$!")
/opt/yodyod/runtime/browser.sh &
browser_pid=$!
pids+=("$browser_pid")
node /opt/yodyod/gateway/dist/server/server/index.js &
pids+=("$!")
ttyd --writable --port 7681 --max-clients 8 --cwd "$GATEWAY_WORKSPACE_DIR" bash --login &
pids+=("$!")

log "Starting desktop :6080, terminal :7681, shared Chrome on loopback :9222, Codex gateway :$PORT."
set +e
wait -n "${pids[@]}"
status=$?
set -e
log "A supervised service exited (status $status); stopping the instance runtime."
cleanup
((status != 0)) || status=1
exit "$status"
