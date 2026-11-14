#!/bin/bash
set -euo pipefail
export DISPLAY=:1
profile="${HOME:-/root}/.config/yodyod/chrome"
mkdir -p "$profile"
for ((attempt=0; attempt<120; attempt++)); do
  if xdpyinfo >/dev/null 2>&1; then break; fi
  sleep 1
done
xdpyinfo >/dev/null 2>&1 || { echo 'X desktop did not become ready.' >&2; exit 1; }

# A stopped instance may leave Chromium locks; never remove a live browser's lock.
if ! curl -fsS --max-time 2 http://127.0.0.1:9222/json/version >/dev/null; then
  rm -f "$profile/SingletonLock" "$profile/SingletonCookie" "$profile/SingletonSocket"
fi
# Chrome runs as root inside an isolated Agent37 instance; disable its sandbox.
# DevTools is loopback-only; never configure 9222 as a public port.
while true; do
  google-chrome-stable \
    --no-sandbox --disable-dev-shm-usage --no-first-run --no-default-browser-check \
    --remote-debugging-address=127.0.0.1 --remote-debugging-port=9222 \
    --user-data-dir="$profile" --password-store=basic --start-maximized \
    about:blank || true
  sleep 2
done
