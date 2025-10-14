#!/usr/bin/env bash
set -euo pipefail

ENV_FILES=(--env-file .env)
[ -f ./.env.local ] && ENV_FILES+=(--env-file .env.local)

echo "🔐 Ensuring DB users & grants…"

# Získej (případně spusť) app kontejner kvůli IP
APP_CID="$(docker compose "${ENV_FILES[@]}" ps -q app || true)"
if [[ -z "${APP_CID}" ]]; then
  echo "ℹ️  App container not running yet → starting it to fetch IP…"
  docker compose "${ENV_FILES[@]}" up -d app >/dev/null
  APP_CID="$(docker compose "${ENV_FILES[@]}" ps -q app)"
fi
APP_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$APP_CID" 2>/dev/null || true)"

# Spusť granty uvnitř DB kontejneru, APP_IP pošleme jako env
docker compose "${ENV_FILES[@]}" exec -T \
  -e APP_IP="${APP_IP}" \
  db sh -lc '
set -e

SQL="/tmp/grants.sql"

# 1) Základní grants: user@"%" + vyčištění typických variant
cat > "$SQL" <<EOSQL
DROP USER IF EXISTS '\''$MARIADB_USER'\''@'\''%'\'';
DROP USER IF EXISTS '\''$MARIADB_USER'\''@'\''localhost'\'';
DROP USER IF EXISTS '\''$MARIADB_USER'\''@'\''127.0.0.1'\'';
DROP USER IF EXISTS '\''$MARIADB_USER'\''@'\''::1'\'';
CREATE USER '\''$MARIADB_USER'\''@'\''%'\'' IDENTIFIED BY '\''$MARIADB_PASSWORD'\'';
GRANT ALL PRIVILEGES ON \`$MARIADB_DATABASE\`.* TO '\''$MARIADB_USER'\''@'\''%'\'';
EOSQL

# 2) Pokud máme IP app kontejneru, přidej explicitní user@IP
if [ -n "${APP_IP:-}" ]; then
  cat >> "$SQL" <<EOSQL
DROP USER IF EXISTS '\''$MARIADB_USER'\''@'\''$APP_IP'\'';
CREATE USER '\''$MARIADB_USER'\''@'\''$APP_IP'\'' IDENTIFIED BY '\''$MARIADB_PASSWORD'\'';
GRANT ALL PRIVILEGES ON \`$MARIADB_DATABASE\`.* TO '\''$MARIADB_USER'\''@'\''$APP_IP'\'';
EOSQL
fi

# 3) Final
cat >> "$SQL" <<EOSQL
FLUSH PRIVILEGES;
EOSQL

mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" < "$SQL"
rm -f "$SQL"

if [ -n "${APP_IP:-}" ]; then
  echo "✅ DB users ready (user@'%' + user@'${APP_IP}')"
else
  echo "✅ DB user ready (user@'%')"
fi
'

