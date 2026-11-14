#!/bin/bash
# XFCE/noVNC without dockerd, compatible with Agent37 Standard (gVisor).
set -euo pipefail
export DISPLAY=:1
desktop_port="${AGENT37_DESKTOP_PORT:-6080}"
vnc_port="${AGENT37_DESKTOP_VNC_PORT:-5900}"
geometry="${AGENT37_SCREEN_GEOMETRY:-1440x900x24}"
profile="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$profile" "$HOME/Desktop" "$HOME/.agent37"
if [[ ! -f "$profile/xfce4-panel.xml" ]]; then
  cp /etc/xdg/xfce4/panel/default.xml "$profile/xfce4-panel.xml"
fi
# gVisor has no GPU. Avoid probing GL/compositing in the window manager.
if [[ ! -f "$profile/xfce4-session.xml" ]]; then
  python3 - "$profile/xfce4-session.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
tree = ET.parse('/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml')
for prop in tree.iter('property'):
    if prop.get('name') == 'Client0_Command' and any(v.get('value') == 'xfwm4' for v in prop):
        for value in ('--compositor=off', '--vblank=off'):
            ET.SubElement(prop, 'value', type='string', value=value)
tree.write(sys.argv[1], encoding='UTF-8', xml_declaration=True)
PY
fi
if [[ ! -f "$HOME/.agent37/desktop-icons-seeded" ]]; then
  for app in xfce4-terminal; do
    if [[ -f "/usr/share/applications/$app.desktop" ]]; then
      install -m 0755 "/usr/share/applications/$app.desktop" "$HOME/Desktop/"
    fi
  done
  touch "$HOME/.agent37/desktop-icons-seeded"
fi

pids=()
cleanup() {
  trap - TERM INT
  if ((${#pids[@]})); then
    kill "${pids[@]}" 2>/dev/null || true
    wait "${pids[@]}" 2>/dev/null || true
  fi
}
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 130' INT

respawn() {
  local log="$1" child
  shift
  trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 0' TERM INT
  while true; do
    "$@" >>"$log" 2>&1 &
    child=$!
    wait "$child" || true
    sleep 2 &
    child=$!
    wait "$child" || true
  done
}

rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
respawn /tmp/xvnc.log Xtigervnc "$DISPLAY" \
  -geometry "${geometry%x*}" -depth "${geometry##*x}" \
  -rfbport "$vnc_port" -localhost -SecurityTypes None -AlwaysShared -desktop YodYod -ac &
pids+=("$!")
for ((attempt=0; attempt<120; attempt++)); do
  if xdpyinfo >/dev/null 2>&1; then break; fi
  sleep 1
done
if ! xdpyinfo >/dev/null 2>&1; then cleanup; exit 1; fi
respawn /tmp/xfce.log dbus-run-session -- xfce4-session &
pids+=("$!")
respawn /tmp/novnc.log websockify --web /usr/share/novnc "$desktop_port" "localhost:$vnc_port" &
pids+=("$!")
wait -n "${pids[@]}"
cleanup
exit 1
