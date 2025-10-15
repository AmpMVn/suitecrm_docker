#!/usr/bin/env bash
set -euo pipefail

# Předáme .env Dockeru (kvůli docker compose substituci)
ENV_FILES=(--env-file .env)
[ -f ./.env.local ] && ENV_FILES+=(--env-file .env.local)

# Načti env z hosta a připrav SITE_URL
set -a
[ -f ./.env ] && . ./.env
[ -f ./.env.local ] && . ./.env.local
set +a

# Preferuj SITE_URL z envu, jinak odvoď z portu; odstraň trailing slash
SITE_URL="${SITE_URL:-http://localhost:${SUITECRM_WEB_PORT_HOST:-8080}}"
SITE_URL="${SITE_URL%/}"

echo "→ SuiteCRM CLI install (script)"
echo "   Using SITE_URL: ${SITE_URL}"

# Spusť uvnitř app: sanity check, PURGE, PATCH InstallHandler, instalátor
# (předáme SITE_URL do prostředí procesu uvnitř kontejneru)
if ! docker compose "${ENV_FILES[@]}" run --rm -T -e SITE_URL="${SITE_URL}" app bash -lc '
  set -euo pipefail

  echo "↪ sanity check: mysqli connect using app env"
  php -r '"'"'$h=getenv("DB_HOST"); $u=getenv("DB_USER"); $p=getenv("DB_PASSWORD"); $d=getenv("DB_NAME"); $port=intval(getenv("DB_PORT")?:3306); $m=@new mysqli($h,$u,$p,$d,$port); if($m && !$m->connect_errno){echo "OK\n"; exit(0);} fwrite(STDERR, "ERR: ".($m?$m->connect_error:"no mysqli")."\n"); exit(1);'"'"'

  echo "↪ purging old SuiteCRM configs & cache (to avoid stale DB creds)"
  rm -f public/legacy/config.php public/legacy/config_override.php || true
  rm -rf var/cache/* var/log/* || true
  # Symfony env cache
  rm -f .env.local.php || true

  # === BACKUP: .env.local (pokud existuje) ===
  if [ -f .env.local ]; then
    echo "↪ backing up existing .env.local"
    cp .env.local /tmp/.env.local.preinstall
  fi

  # --- PATCH: skip .env.local creation if it already exists ---
  echo "↪ patching SuiteCRM installer to respect existing .env.local"
  f="src/App/Install/LegacyHandler/InstallHandler.php"
  if [ -f "$f" ] && ! grep -q "Skipping .env.local creation" "$f"; then
    # vloží podmínku do createEnv() hned po chdir($this->projectDir);
    awk "/chdir\\(\\\\\\$this->projectDir\\);/ && !done { \
      print; \
      print \"\"; \
      print \"            // Skip if user already provides their own .env.local\"; \
      print \"            if ((new \\\\\\\\Symfony\\\\\\\\Component\\\\\\\\Filesystem\\\\\\\\Filesystem())->exists(\\x27.env.local\\x27)) {\"; \
      print \"                \\\\\\$this->logger->info(\\x27Skipping .env.local creation: file already exists\\x27);\"; \
      print \"                chdir(\\\\\\$this->legacyDir);\"; \
      print \"                return true;\"; \
      print \"            }\"; \
      done=1; next }1" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
  # --- END PATCH ---

  echo "↪ running installer"
  php -d upload_max_filesize=20M -d post_max_size=20M \
    bin/console suitecrm:app:install \
      -u "admin" \
      -p "admin" \
      -U "$DB_USER" \
      -P "$DB_PASSWORD" \
      -H "$DB_HOST" \
      -N "$DB_NAME" \
      -S "$SITE_URL" \
      -d "no"

  # === RESTORE: .env.local po instalaci (pokud byla záloha) ===
  if [ -f /tmp/.env.local.preinstall ]; then
    echo "↪ restoring your .env.local (preserving APP_SECRET if needed)"
    GEN_APP_SECRET=""
    if [ -f .env.local ]; then
      GEN_APP_SECRET="$(grep -E '^APP_SECRET=' .env.local || true)"
    fi
    if grep -qE "^APP_SECRET=" /tmp/.env.local.preinstall; then
      cp /tmp/.env.local.preinstall .env.local
    else
      if [ -n "$GEN_APP_SECRET" ]; then
        { cat /tmp/.env.local.preinstall; echo "$GEN_APP_SECRET"; } > .env.local
      else
        NEW_APP_SECRET="$(php -r "echo bin2hex(random_bytes(16));")"
        { cat /tmp/.env.local.preinstall; echo "APP_SECRET=$NEW_APP_SECRET"; } > .env.local
      fi
    fi
    rm -f /tmp/.env.local.preinstall
  fi
'; then
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
