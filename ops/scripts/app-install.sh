#!/usr/bin/env bash
set -euo pipefail

# Předáme .env Dockeru
ENV_FILES=(--env-file .env)
[ -f ./.env.local ] && ENV_FILES+=(--env-file .env.local)

# Načti port z hostího .env
set -a
[ -f ./.env ] && . ./.env
[ -f ./.env.local ] && . ./.env.local
set +a

PORT="${SUITECRM_APP_PORT:-8080}"
SITE_URL="http://localhost:${PORT}"

echo "→ SuiteCRM CLI install (script)"
echo "   Using SITE_URL: ${SITE_URL}"

# Spusť uvnitř app: sanity check, PURGE starých konfiguráků/cache, pak instalátor
if ! docker compose "${ENV_FILES[@]}" exec -T app bash -lc '
  set -euo pipefail

  echo "↪ sanity check: mysqli connect using app env"
  php -r '"'"'$h=getenv("DB_HOST"); $u=getenv("DB_USER"); $p=getenv("DB_PASSWORD"); $d=getenv("DB_NAME"); $port=intval(getenv("DB_PORT")?:3306); $m=@new mysqli($h,$u,$p,$d,$port); if($m && !$m->connect_errno){echo "OK\n"; exit(0);} fwrite(STDERR, "ERR: ".($m?$m->connect_error:"no mysqli")."\n"); exit(1);'"'"'

  echo "↪ purging old SuiteCRM configs & cache (to avoid stale DB creds)"
  rm -f public/legacy/config.php public/legacy/config_override.php || true
  rm -rf var/cache/* var/log/* || true
  # Symfony env cache
  rm -f .env.local.php || true

  echo "↪ running installer"
  php -d upload_max_filesize=20M -d post_max_size=20M \
    bin/console suitecrm:app:install \
      -u "admin" \
      -p "admin" \
      -U "$DB_USER" \
      -P "$DB_PASSWORD" \
      -H "$DB_HOST" \
      -N "$DB_NAME" \
      -S "__SITE_URL__" \
      -d "no"
' | sed "s|__SITE_URL__|${SITE_URL}|"; then
  echo "❌ Installer failed — printing grants for debug (both @% and @appIP):"
  docker compose "${ENV_FILES[@]}" exec -T db sh -lc '
    appip=$(getent hosts app 2>/dev/null | awk "{print \$1; exit}" || true)
    echo "User,Host,Plugin:"; mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "
      SELECT user,host,plugin FROM mysql.user WHERE user=\"$MARIADB_USER\";
    "
    echo "Grants @%:"; mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "
      SHOW GRANTS FOR \"$MARIADB_USER\"@\"%\";
    " || true
    if [ -n "$appip" ]; then
      echo "Grants @$appip:"; mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "
        SHOW GRANTS FOR \"$MARIADB_USER\"@\"$appip\";
      " || true
    fi
  '
  exit 1
fi

echo "✅ SuiteCRM installed"
