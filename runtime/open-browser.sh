#!/bin/bash
# One launch per user request. The durable profile is shared with browser MCPs.
set -euo pipefail
export DISPLAY=:1
profile="${HOME:-/root}/.config/yodyod/chrome"
mkdir -p "$profile"
if (($# == 0)); then set -- about:blank; fi
exec google-chrome-stable \
  --no-sandbox --disable-dev-shm-usage --no-first-run --no-default-browser-check \
  --remote-debugging-address=127.0.0.1 --remote-debugging-port=9222 \
  --user-data-dir="$profile" --password-store=basic --start-maximized "$@"
