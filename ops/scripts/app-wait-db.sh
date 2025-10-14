#!/usr/bin/env bash
set -euo pipefail

ENV_FILES=(--env-file .env)
[ -f ./.env.local ] && ENV_FILES+=(--env-file .env.local)

TRIES=60
SLEEP=2
REPAIRED=0

echo "⏳ Testing DB login from app container (mysqli)…"
for i in $(seq 1 "$TRIES"); do
  # Spusť krátký PHP skript v app, vytiskni důvod chyby (connect_error)
  if docker compose "${ENV_FILES[@]}" exec -T app sh -lc 'php -r "
    \$h=getenv(\"DB_HOST\"); \$u=getenv(\"DB_USER\"); \$p=getenv(\"DB_PASSWORD\");
    \$d=getenv(\"DB_NAME\"); \$port=intval(getenv(\"DB_PORT\")?:3306);
    \$m=@new mysqli(\$h,\$u,\$p,\$d,\$port);
    if (\$m && !\$m->connect_errno) { echo \"OK\n\"; exit(0); }
    echo \"ERR: \".(\$m? \$m->connect_error : \"mysqli not available\").\"\n\"; exit(1);
  "' 2>/dev/null | grep -q '^OK$'; then
    echo "✅ App → DB login OK"
    exit 0
  else
    # Získej text chyby pro rozhodnutí
    ERR="$(docker compose "${ENV_FILES[@]}" exec -T app sh -lc 'php -r "
      \$h=getenv(\"DB_HOST\"); \$u=getenv(\"DB_USER\"); \$p=getenv(\"DB_PASSWORD\");
      \$d=getenv(\"DB_NAME\"); \$port=intval(getenv(\"DB_PORT\")?:3306);
      \$m=@new mysqli(\$h,\$u,\$p,\$d,\$port);
      echo (\$m? \$m->connect_error : \"mysqli not available\");
    "' 2>/dev/null || true)"

    echo "   ($i/$TRIES) … $ERR"

    # Pokud je to typické "Access denied", jednou zkusíme granty opravovat automaticky a hned retest
    if [[ "$ERR" == Access\ denied* && "$REPAIRED" -eq 0 ]]; then
      echo "🧯 Detected 'Access denied' from app. Repairing grants (db-ensure-user)…"
      make db-ensure-user || true
      REPAIRED=1
      sleep 2
      continue
    fi
  fi
  sleep "$SLEEP"
done

echo "❌ App → DB login still failing."
docker compose "${ENV_FILES[@]}" exec -T app sh -lc 'echo "DB_HOST=$DB_HOST DB_NAME=$DB_NAME DB_USER=$DB_USER DB_PORT=$DB_PORT"'
exit 1
