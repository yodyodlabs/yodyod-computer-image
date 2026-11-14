#!/bin/bash
set -euo pipefail
export DISPLAY=:1
profile="${HOME:-/root}/.config/yodyod/chrome"
mkdir -p "$profile"
chrome_pid=""
shutdown() {
  trap - TERM INT
  # The user may have closed the boot window and reopened Chrome through XFCE.
  # That process belongs to the launcher, so read the current profile owner.
  local owner
  owner="$(readlink "$profile/SingletonLock" 2>/dev/null || true)"
  if [[ "${owner##*-}" =~ ^[0-9]+$ ]]; then chrome_pid="${owner##*-}"; fi
  if curl -fsS --max-time 2 http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
    # Browser.close flushes the durable profile. SIGTERM can skip pending cookie
    # writes; a group-wide signal must not kill Chrome before this step.
    timeout 10s node --input-type=module <<'JS' || true
const response = await fetch('http://127.0.0.1:9222/json/version', { signal: AbortSignal.timeout(2000) });
const { webSocketDebuggerUrl } = await response.json();
await new Promise((resolve, reject) => {
  const socket = new WebSocket(webSocketDebuggerUrl);
  const timer = setTimeout(() => { socket.close(); reject(new Error('Browser.close timed out')); }, 5000);
  socket.addEventListener('open', () => socket.send(JSON.stringify({ id: 1, method: 'Browser.close' })));
  socket.addEventListener('close', () => { clearTimeout(timer); resolve(); });
  socket.addEventListener('error', () => { clearTimeout(timer); reject(new Error('Browser.close failed')); });
});
JS
  fi
  if [[ -n "$chrome_pid" ]]; then
    for ((attempt=0; attempt<50; attempt++)); do
      if ! kill -0 "$chrome_pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    kill "$chrome_pid" 2>/dev/null || true
    wait "$chrome_pid" 2>/dev/null || true
  fi
  exit 0
}
trap shutdown TERM INT
for ((attempt=0; attempt<120; attempt++)); do
  if xdpyinfo >/dev/null 2>&1; then break; fi
  sleep 1
done
xdpyinfo >/dev/null 2>&1 || { echo 'X desktop did not become ready.' >&2; exit 1; }

# A stopped instance may leave Chromium locks; never remove a live browser's lock.
if ! curl -fsS --max-time 2 http://127.0.0.1:9222/json/version >/dev/null; then
  rm -f "$profile/SingletonLock" "$profile/SingletonCookie" "$profile/SingletonSocket"
fi
# Open once at boot. Closing the browser is a user action, not a service crash.
# Stay available for orderly profile shutdown without reopening any windows.
/opt/yodyod/runtime/open-browser.sh &
chrome_pid=$!
wait "$chrome_pid" || true
chrome_pid=""
while true; do
  sleep 86400 &
  wait "$!" || true
done
