#!/usr/bin/env bash
set -Eeuo pipefail

echo "→ SuiteCRM CLI install (script)"

APP_ENV="${APP_ENV:-dev}"

# Host/URL pro instalátor (nové CLI chce --site_host)
WEB_HOST="${SUITECRM_WEB_HOST:-127.0.0.1}"
WEB_PORT="${SUITECRM_WEB_PORT_HOST:-8180}"
SITE_HOST="${SITE_HOST:-${WEB_HOST}:${WEB_PORT}}"

# Admin přihlašky
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"

# DB env (podpora jak DB_* tak SUITECRM_DB_*)
DB_HOST="${DB_HOST:-${SUITECRM_DB_HOST:-db}}"
DB_PORT="${DB_PORT:-${SUITECRM_DB_PORT:-3306}}"
DB_NAME="${DB_NAME:-${SUITECRM_DB_NAME:-suitecrm}}"
DB_USER="${DB_USER:-${SUITECRM_DB_USER:-suitecrm}}"
DB_PASSWORD="${DB_PASSWORD:-${SUITECRM_DB_PASSWORD:-secret}}"

# 1) Composer install pokud chybí vendor (bez skriptů – ty řešíme manuálně po instalaci)
if [ ! -f vendor/autoload.php ]; then
  echo "↪ Running composer install (no scripts)"
  COMPOSER_MEMORY_LIMIT=-1 SYMFONY_SKIP_ENV_CHECK=1 composer install --no-interaction --prefer-dist --optimize-autoloader --no-scripts
fi

# 2) Test DB připojení (heredoc, žádná bash expanze)
php <<'PHP'
<?php
$h = getenv('DB_HOST') ?: (getenv('SUITECRM_DB_HOST') ?: 'db');
$u = getenv('DB_USER') ?: (getenv('SUITECRM_DB_USER') ?: 'suitecrm');
$p = getenv('DB_PASSWORD') ?: (getenv('SUITECRM_DB_PASSWORD') ?: 'secret');
$n = getenv('DB_NAME') ?: (getenv('SUITECRM_DB_NAME') ?: 'suitecrm');
$port = (int)(getenv('DB_PORT') ?: (getenv('SUITECRM_DB_PORT') ?: 3306));
mysqli_report(MYSQLI_REPORT_OFF);
$m = @new mysqli($h,$u,$p,$n,$port);
if ($m->connect_errno) {
  fwrite(STDERR, "DB connect failed: ".$m->connect_error."\n");
  exit(2);
}
echo "OK\n";
PHP

# 3) Zjisti počet tabulek
TABLES="$(php <<'PHP'
<?php
$h = getenv('DB_HOST') ?: (getenv('SUITECRM_DB_HOST') ?: 'db');
$u = getenv('DB_USER') ?: (getenv('SUITECRM_DB_USER') ?: 'suitecrm');
$p = getenv('DB_PASSWORD') ?: (getenv('SUITECRM_DB_PASSWORD') ?: 'secret');
$n = getenv('DB_NAME') ?: (getenv('SUITECRM_DB_NAME') ?: 'suitecrm');
$port = (int)(getenv('DB_PORT') ?: (getenv('SUITECRM_DB_PORT') ?: 3306));
$m = new mysqli($h,$u,$p,$n,$port);
$q = $m->query("SELECT COUNT(*) c FROM information_schema.tables WHERE table_schema='".$m->real_escape_string($n)."'");
echo ($q && ($row=$q->fetch_assoc())) ? (int)$row['c'] : 0;
PHP
)"
TABLES="${TABLES:-0}"
echo "ℹ️  DB tables: ${TABLES}"

NEED_INSTALL=0
if [ "$TABLES" -lt 10 ]; then
  echo "⚠️  DB looks empty → forcing SuiteCRM install"
  NEED_INSTALL=1
fi

# 4) Pokud je DB prázdná → smaž legacy configy a proveď instalaci
if [ "$NEED_INSTALL" = "1" ]; then
  rm -f public/legacy/config.php public/legacy/config_override.php || true

  # Zjisti, jaké přepínače instalátor podporuje (nové vs. staré)
  INSTALL_HELP="$(php bin/console suitecrm:app:install -h 2>&1 || true)"

  if printf "%s" "$INSTALL_HELP" | grep -q -- "--db_username"; then
    # NOVÉ přepínače
    INSTALL_CMD=$(
      cat <<EOF
php bin/console suitecrm:app:install \
  --db_host="${DB_HOST}" \
  --db_port="${DB_PORT}" \
  --db_username="${DB_USER}" \
  --db_password="${DB_PASSWORD}" \
  --db_name="${DB_NAME}" \
  --site_host="${SITE_HOST}" \
  --site_username="${ADMIN_USER}" \
  --site_password="${ADMIN_PASS}" \
  --no-interaction
EOF
    )
  else
    # STARŠÍ přepínače (fallback)
    # Pozor: staré CLI používalo --site_url + --admin_user/--admin_pass
    INSTALL_CMD=$(
      cat <<EOF
php bin/console suitecrm:app:install \
  --db_host="${DB_HOST}" \
  --db_port="${DB_PORT}" \
  --db_user="${DB_USER}" \
  --db_pass="${DB_PASSWORD}" \
  --db_name="${DB_NAME}" \
  --site_url="http://${SITE_HOST}" \
  --admin_user="${ADMIN_USER}" \
  --admin_pass="${ADMIN_PASS}" \
  --no-interaction
EOF
    )
  fi

  echo "↪ Running installer:"
  echo "   $INSTALL_CMD"
  eval "$INSTALL_CMD"

  # Rychlá kontrola, že vznikly tabulky
  TABLES_AFTER="$(php <<'PHP'
<?php
$h = getenv('DB_HOST') ?: (getenv('SUITECRM_DB_HOST') ?: 'db');
$u = getenv('DB_USER') ?: (getenv('SUITECRM_DB_USER') ?: 'suitecrm');
$p = getenv('DB_PASSWORD') ?: (getenv('SUITECRM_DB_PASSWORD') ?: 'secret');
$n = getenv('DB_NAME') ?: (getenv('SUITECRM_DB_NAME') ?: 'suitecrm');
$port = (int)(getenv('DB_PORT') ?: (getenv('SUITECRM_DB_PORT') ?: 3306));
$m = new mysqli($h,$u,$p,$n,$port);
$q = $m->query("SELECT COUNT(*) c FROM information_schema.tables WHERE table_schema='".$m->real_escape_string($n)."'");
echo ($q && ($row=$q->fetch_assoc())) ? (int)$row['c'] : 0;
PHP
  )"
  echo "ℹ️  DB tables after install: ${TABLES_AFTER:-0}"
fi

# 5) Cache až po (re)instalaci
echo "↪ Clearing cache"
php bin/console cache:clear || true
php bin/console cache:warmup || true

echo "✅ Installer finished (${APP_ENV}, SITE_HOST=${SITE_HOST})"
