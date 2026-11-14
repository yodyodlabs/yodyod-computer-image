#!/bin/bash
set -euo pipefail
image="${1:?Usage: scripts/smoke-test.sh IMAGE}"
# Docker can create a missing WorkingDir; the Agent37 VM launcher cannot. Keep
# startup outside the empty persistent mount so bootstrap can create its files.
test "$(docker image inspect "$image" --format '{{.Config.WorkingDir}}')" = /
name="yodyod-smoke-${RANDOM}"
volume="${name}-home"
cleanup() {
  status=$?
  if ((status != 0)); then
    docker logs --tail 200 "$name" >&2 || true
    mkdir -p artifacts
    docker exec "$name" scrot --overwrite /tmp/smoke-failure.png || true
    docker cp "$name:/tmp/smoke-failure.png" artifacts/smoke-failure.png || true
  fi
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker volume rm "$volume" >/dev/null 2>&1 || true
  return "$status"
}
trap cleanup EXIT
docker volume create "$volume" >/dev/null
docker run --detach --name "$name" --shm-size=1g \
  --mount "type=volume,source=$volume,target=/root,volume-nocopy" "$image" >/dev/null

wait_ready() {
  for ((attempt=0; attempt<120; attempt++)); do
    if docker exec "$name" /opt/yodyod/runtime/healthcheck.sh >/dev/null 2>&1; then return; fi
    if [[ "$(docker inspect --format '{{.State.Running}}' "$name")" != true ]]; then
      echo 'Container exited before becoming ready.' >&2; return 1
    fi
    sleep 2
  done
  echo 'Container readiness timed out.' >&2
  return 1
}

wait_ready
docker exec --workdir /opt/yodyod/tools "$name" npm run check
docker exec --workdir /opt/yodyod/tools "$name" npm test
docker exec -e YODYOD_SOURCE_ROOT=/opt/yodyod "$name" \
  python3 -m unittest discover -s /opt/yodyod/tools/tests -p 'test_*.py' -v
docker exec "$name" codex --version
docker exec "$name" browser-use --version
docker exec "$name" node /opt/yodyod/tools/tests/smoke.mjs

docker exec "$name" sh -c 'printf persistent > /root/workspace/.yodyod-smoke'
docker restart --time 20 "$name" >/dev/null
wait_ready
test "$(docker exec "$name" cat /root/workspace/.yodyod-smoke)" = persistent
docker exec "$name" node /opt/yodyod/tools/tests/smoke.mjs --after-restart
docker exec "$name" node /opt/yodyod/tools/tests/browser-lifecycle.mjs
echo 'PASS image smoke tests, including persistent-home and Chrome-profile restart'
