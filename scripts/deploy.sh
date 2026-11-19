#!/usr/bin/env bash
#
# Build and install into the running container.
#
# The point of this script is the verification at the end: a stale module jar in
# the container once cost a full day of every message failing with "the agent
# worker stopped before this turn finished", because the copy that got deployed
# was an older build than the source. Copying is not deploying until the bytes
# in the container are the bytes that were built.
#
# Usage: scripts/deploy.sh [--no-frontend]

set -euo pipefail

container="${AKIBA_CONTAINER:-akiba}"
root="$(cd "$(dirname "$0")/.." && pwd)"
skip_frontend=0
[ "${1:-}" = "--no-frontend" ] && skip_frontend=1

cd "$root"

echo "==> building"
./gradlew :akiba_framework:jar :akiba_mod_utils:moduleJar-AkibaUtils --console=plain -q

framework_jar="$(ls -t subprojects/akiba_framework/build/libs/akiba_framework-*.jar \
  | grep -v sources | head -1)"
module_jar="subprojects/akiba_mod_utils/build/libs/amod-AkibaUtils-1.2.jar"

for jar in "$framework_jar" "$module_jar"; do
  [ -f "$jar" ] || { echo "missing build output: $jar" >&2; exit 1; }
done

echo "==> installing $(basename "$framework_jar")"
docker cp "$framework_jar" "$container:/home/akiba/akiba_framework/lib/$(basename "$framework_jar")"
# Older builds of the same artifact would be loaded beside it.
docker exec "$container" sh -c "ls /home/akiba/akiba_framework/lib/akiba_framework-*.jar" \
  | grep -v "$(basename "$framework_jar")" \
  | while read -r stale; do
      echo "    removing stale $(basename "$stale")"
      docker exec "$container" rm -f "$stale"
    done

echo "==> installing $(basename "$module_jar")"
docker cp "$module_jar" "$container:/home/akiba/akiba_framework/modules/$(basename "$module_jar")"

echo "==> verifying the module jar in the container"
local_sum="$(sha256sum "$module_jar" | cut -d' ' -f1)"
remote_sum="$(docker exec "$container" sha256sum \
  "/home/akiba/akiba_framework/modules/$(basename "$module_jar")" | cut -d' ' -f1)"
if [ "$local_sum" != "$remote_sum" ]; then
  echo "module jar in the container is not the one that was built:" >&2
  echo "  built:     $local_sum" >&2
  echo "  container: $remote_sum" >&2
  exit 1
fi
echo "    $local_sum"

if [ "$skip_frontend" -eq 0 ]; then
  echo "==> building the frontend"
  ( cd subprojects/akiba_frontend && npm run build >/dev/null )
  docker exec "$container" sh -c 'rm -rf /home/akiba/akiba_frontend/dist.new'
  docker cp subprojects/akiba_frontend/dist "$container:/home/akiba/akiba_frontend/dist.new"
  docker exec "$container" sh -c '
    cp -r /home/akiba/akiba_frontend/dist /home/akiba/akiba_frontend/dist.prev 2>/dev/null || true
    rm -rf /home/akiba/akiba_frontend/dist
    mv /home/akiba/akiba_frontend/dist.new /home/akiba/akiba_frontend/dist'
fi

echo "==> restarting $container"
docker restart "$container" >/dev/null

echo "==> waiting for the web interface"
for _ in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1/ || true)"
  [ "$code" = "200" ] && { echo "    web=200"; exit 0; }
  sleep 2
done

echo "the web interface did not come back within 60s" >&2
exit 1
