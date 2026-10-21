#!/usr/bin/env bash
set -euo pipefail
image="${1:?image required}"
name="cloudrec-smoke-${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-1}"
tmp="$(mktemp -d)"
# MySQL drops privileges before reading initialization scripts.
chmod 755 "$tmp"
cleanup() {
  docker rm -f "$name-app" "$name-db" >/dev/null 2>&1 || true
  docker network rm "$name" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT
docker network create "$name" >/dev/null
root_password="$(openssl rand -hex 24)"
app_password="$(openssl rand -hex 24)"
if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
  echo "::add-mask::$root_password"
  echo "::add-mask::$app_password"
fi
docker run --rm --user 0 --entrypoint cp -v "$tmp:/init" "$image" /cloudrec/db/init.sql /init/00-schema.sql
# The SQL contains only the existing upstream initialization, never cloud keys.
docker run -d --name "$name-db" --network "$name" --network-alias mysql-local \
  -e MYSQL_ROOT_PASSWORD="$root_password" -e MYSQL_DATABASE=cloudrec_db \
  -e MYSQL_USER=cloudrec -e MYSQL_PASSWORD="$app_password" \
  -v "$tmp:/docker-entrypoint-initdb.d:ro" mysql:8.0.40 >/dev/null
for ((i=0;i<120;i++)); do
  if docker exec -e MYSQL_PWD="$app_password" "$name-db" \
    mysql -h127.0.0.1 -ucloudrec cloudrec_db -Nse 'SELECT COUNT(*) FROM user' >/dev/null 2>&1; then break; fi
  sleep 2
done
docker exec -e MYSQL_PWD="$app_password" "$name-db" \
  mysql -h127.0.0.1 -ucloudrec cloudrec_db -Nse 'SELECT COUNT(*) FROM user' >/dev/null
docker run -d --name "$name-app" --network "$name" -p 127.0.0.1::8080 \
  -e DB_PASSWORD="$app_password" -e SPRING_DATASOURCE_USERNAME=cloudrec \
  -e JAVA_TOOL_OPTIONS=-Xmx1536m "$image" >/dev/null
port="$(docker port "$name-app" 8080/tcp | awk -F: '{print $NF}')"
for ((i=0;i<120;i++)); do
  if curl -fsS "http://127.0.0.1:$port/index.html" -o "$tmp/index.html" 2>/dev/null; then break; fi
  [[ "$(docker inspect -f '{{.State.Running}}' "$name-app")" == true ]] || {
    echo 'CloudRec process exited before readiness' >&2; exit 1;
  }
  sleep 2
done
curl -fsS "http://127.0.0.1:$port/index.html" -o "$tmp/index.html"
grep -qi '<html' "$tmp/index.html"
# Verify the actual frontend bundle is served, rather than an HTML error page.
asset="$(sed -nE 's/.*src="([^"]+\.js)".*/\1/p' "$tmp/index.html" | head -1)"
[[ -n "$asset" ]] || { echo 'frontend JS bundle missing' >&2; exit 1; }
curl -fsS "http://127.0.0.1:$port/${asset#/}" -o "$tmp/app.js"
[[ -s "$tmp/app.js" ]]
echo 'PASS: initialized MySQL schema, application startup and frontend bundle'
