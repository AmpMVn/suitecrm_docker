#!/usr/bin/env bash
set -euo pipefail

echo "⏳ Waiting for DB container..."

# Načti .env a .env.local do prostředí (kvůli SUITECRM_* proměnným)
set -a
[ -f ./.env ] && . ./.env
[ -f ./.env.local ] && . ./.env.local
set +a

ENV_FILES=(--env-file .env)
[ -f ./.env.local ] && ENV_FILES+=(--env-file .env.local)

PROJECT_NAME="${SUITECRM_PROJECT_NAME:-suitecrm}"
DATA_DIR="./.data/${PROJECT_NAME}/mariadb"
AUTO_FIX="${SUITECRM_AUTO_FIX_DB:-1}"
TRIES=60

# Zajisti, že mount cílová složka existuje (jinak DB nenastartuje)
mkdir -p "${DATA_DIR}"
docker compose "${ENV_FILES[@]}" up -d db >/dev/null

CID="$(docker compose "${ENV_FILES[@]}" ps -q db || true)"
if [[ -z "${CID}" ]]; then
  echo "❌ DB container not found after up."
  exit 1
fi

# --- Test DB funkčnosti ---
function test_db() {
  local status health
  status="$(docker inspect -f '{{.State.Status}}' "$CID" 2>/dev/null || echo "missing")"
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$CID" 2>/dev/null || true)"
  echo "   status=${status} health=${health}"

  if [[ "${status}" != "running" ]]; then
    return 1
  fi

  # 1) rychlý ping (stejně jako healthcheck)
  if ! docker compose "${ENV_FILES[@]}" exec -T db sh -lc \
      'mariadb-admin -h 127.0.0.1 -uroot -p"$MARIADB_ROOT_PASSWORD" ping --silent' >/dev/null 2>&1; then
    return 1
  fi

  # 2) minimální query ověření
  if docker compose "${ENV_FILES[@]}" exec -T db sh -lc \
      'mariadb -h 127.0.0.1 -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1'; then
    return 0
  fi

  return 1
}

# --- První čekání ---
for _ in $(seq 1 "${TRIES}"); do
  if test_db; then
    echo "✅ DB ready"
    exit 0
  fi
  sleep 2
done

# Timeout → kontrola logu a případný self-heal
echo "❌ DB not ready in time. Checking logs…"
LOGS="$(docker compose "${ENV_FILES[@]}" logs --tail=200 db 2>/dev/null || true)"
echo "${LOGS}" | tail -n 40

if echo "${LOGS}" | grep -q "Access denied for user 'root'@'localhost'"; then
  echo "🧯 Detected 'Access denied' for root."
  if [[ "${AUTO_FIX}" != "1" ]]; then
    echo "↪ Self-heal disabled (SUITECRM_AUTO_FIX_DB=${AUTO_FIX}). Exiting."
    exit 1
  fi

  [[ -d "${DATA_DIR}" ]] || mkdir -p "${DATA_DIR}"
  if [ -n "$(ls -A "${DATA_DIR}" 2>/dev/null)" ]; then
    TS="$(date +%Y%m%d-%H%M%S)"
    BKP="${DATA_DIR}.bak-${TS}"
    echo "→ Stopping DB & backing up ${DATA_DIR} -> ${BKP}"
    docker compose "${ENV_FILES[@]}" stop db >/dev/null 2>&1 || true
    mv "${DATA_DIR}" "${BKP}"
    mkdir -p "${DATA_DIR}"
    echo "✅ Backup done."
  else
    echo "ℹ️  Data dir empty – re-init without backup."
  fi

  echo "→ Starting fresh DB…"
  docker compose "${ENV_FILES[@]}" up -d db >/dev/null
  CID="$(docker compose "${ENV_FILES[@]}" ps -q db || true)"

  for _ in $(seq 1 "${TRIES}"); do
    if test_db; then
      echo "✅ DB ready after self-heal"
      exit 0
    fi
    sleep 2
  done

  echo "❌ DB still not ready after self-heal."
  exit 1
else
  echo "❌ DB not ready and no root 'Access denied' detected."
  exit 1
fi
