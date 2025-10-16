#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# db-ensure-user.sh
# - Zajistí DB uživatele a GRANTy.
# - Vždy vytvoří user@'%' (dostačující pro Docker síť).
# - user@APP_IP přidá jen pokud umíme zjistit validní IPv4 app kontejneru.
# - Nevytváří žádné závislosti na hostnames typu 'localhost'.
# -------------------------------------------------------------------

ENV_FILES=(--env-file .env)
[ -f ./.env.local ] && ENV_FILES+=(--env-file .env.local)

echo "🔐 Ensuring DB users & grants…"

# --- Helper: zjistí IPv4 app kontejneru (pokud existuje) ---
get_app_ipv4() {
  local cid ip
  cid="$(docker compose "${ENV_FILES[@]}" ps -q app 2>/dev/null || true)"
  if [[ -z "$cid" ]]; then
    echo "ℹ️  App container not running yet → starting it to fetch IP…"
    docker compose "${ENV_FILES[@]}" up -d app >/dev/null
    cid="$(docker compose "${ENV_FILES[@]}" ps -q app 2>/dev/null || true)"
  fi
  if [[ -z "$cid" ]]; then
    echo ""
    return 0
  fi
  # Vezmeme první IPv4 z připojených sítí
  ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$cid" 2>/dev/null | awk '{print $1}' || true)"
  echo "${ip:-}"
}

# --- Helper: validace jednoduché IPv4 ---
is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  # rozsahy 0–255
  IFS='.' read -r a b c d <<<"$1"
  for n in "$a" "$b" "$c" "$d"; do
    (( n >= 0 && n <= 255 )) || return 1
  done
  return 0
}

APP_IP="$(get_app_ipv4)"
if [[ -n "${APP_IP:-}" ]]; then
  if ! is_ipv4 "$APP_IP"; then
    echo "ℹ️  App IP is not IPv4 ('${APP_IP}'), will skip user@APP_IP grant and use only user@'%'"
    APP_IP=""
  else
    echo "ℹ️  Detected app IPv4: ${APP_IP}"
  fi
else
  echo "ℹ️  App IP not detected, will use only user@'%'"
fi

# --- Spusť granty uvnitř DB kontejneru, APP_IP pošleme jako env ---
docker compose "${ENV_FILES[@]}" exec -T \
  -e APP_IP="${APP_IP:-}" \
  db sh -lc '
set -e

SQL="/tmp/grants.sql"

# 0) Echo pro debug
echo "DB: $MARIADB_DATABASE  User: $MARIADB_USER  Host grants: % ${APP_IP:+, $APP_IP}"

# 1) Základní grants – sjednotíme varianty a vytvoříme user@'%'
cat > "$SQL" <<EOSQL
DROP USER IF EXISTS '\''$MARIADB_USER'\''@'\''%'\'';
DROP USER IF EXISTS '\''$MARIADB_USER'\''@'\''localhost'\'';
DROP USER IF EXISTS '\''$MARIADB_USER'\''@'\''127.0.0.1'\'';
DROP USER IF EXISTS '\''$MARIADB_USER'\''@'\''::1'\'';
CREATE USER '\''$MARIADB_USER'\''@'\''%'\'' IDENTIFIED BY '\''$MARIADB_PASSWORD'\'';
GRANT ALL PRIVILEGES ON \`$MARIADB_DATABASE\`.* TO '\''$MARIADB_USER'\''@'\''%'\'';
EOSQL

# 2) Volitelně přidej user@APP_IP (jen pokud jsme nějakou IP opravdu dostali)
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

