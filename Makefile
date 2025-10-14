SHELL := /bin/bash
.DEFAULT_GOAL := help

# --- Env file chaining (předáváme Dockeru) ---
ENV_FILES=--env-file .env $(if $(wildcard .env.local),--env-file .env.local,)

##@ Docker

.PHONY: up
up: ## Spustí celý stack (docker compose up -d)
	docker compose $(ENV_FILES) up -d

.PHONY: down
down: ## Vypne a odstraní kontejnery (docker compose down)
	docker compose $(ENV_FILES) down

.PHONY: rebuild
rebuild: ## Rebuildne služby app a web bez cache
	docker compose $(ENV_FILES) build --no-cache app web

.PHONY: logs
logs: ## Sleduje logy všech služeb (tail -f)
	docker compose $(ENV_FILES) logs -f --tail=200

.PHONY: ps
ps: ## Zobrazí stav běžících kontejnerů
	docker compose $(ENV_FILES) ps

.PHONY: bash
bash: ## Otevře shell v PHP kontejneru (app)
	docker compose $(ENV_FILES) exec app bash

##@ Node / Yarn

.PHONY: yarn-install
yarn-install: ## Nainstaluje FE závislosti (yarn install)
	docker compose $(ENV_FILES) run --rm node yarn install

.PHONY: yarn-dev
yarn-dev: ## Spustí dev server s otevřenými porty (yarn dev)
	docker compose $(ENV_FILES) run --rm --service-ports node yarn dev

.PHONY: yarn-build
yarn-build: ## Sestaví FE pro produkci (yarn build)
	docker compose $(ENV_FILES) run --rm node yarn build

.PHONY: yarn-watch
yarn-watch: ## Spustí watch mód pro vývoj (yarn watch)
	docker compose $(ENV_FILES) run --rm --service-ports node yarn watch

##@ Database

.PHONY: db-up
db-up: ## Spustí (nebo vytvoří) DB kontejner
	docker compose $(ENV_FILES) up -d db

.PHONY: db-wait
db-wait: ## Čeká na DB + self-heal (auto záloha & reinit při 'Access denied')
	bash ops/scripts/db-wait.sh

.PHONY: db-reset
db-reset: ## DROP & CREATE databáze (destruktivní pro schéma, zachová datový adresář)
	@echo "⚠️  Dropping and creating database..."
	@docker compose $(ENV_FILES) exec -T db sh -lc 'mariadb -uroot -p"$$MARIADB_ROOT_PASSWORD" -e "\
		DROP DATABASE IF EXISTS \`$$MARIADB_DATABASE\`; \
		CREATE DATABASE \`$$MARIADB_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
		CREATE OR REPLACE USER '\''$$MARIADB_USER'\''@'\''%'\'' IDENTIFIED BY '\''$$MARIADB_PASSWORD'\''; \
		CREATE OR REPLACE USER '\''$$MARIADB_USER'\''@'\''localhost'\'' IDENTIFIED BY '\''$$MARIADB_PASSWORD'\''; \
		GRANT ALL PRIVILEGES ON \`$$MARIADB_DATABASE\`.* TO '\''$$MARIADB_USER'\''@'\''%'\''; \
		GRANT ALL PRIVILEGES ON \`$$MARIADB_DATABASE\`.* TO '\''$$MARIADB_USER'\''@'\''localhost'\''; \
		FLUSH PRIVILEGES;"'
	@echo "✅ Database recreated."

.PHONY: db-ensure-user
db-ensure-user:
	bash ops/scripts/db-ensure-user.sh

.PHONY: db-nuke
db-nuke: ## Natrvalo smaže DB data (bind-mount) – přesune do .bak-<timestamp>
	@set -a; [ -f ./.env ] && . ./.env; [ -f ./.env.local ] && . ./.env.local; set +a; \
	DATA_DIR=$${SUITECRM_DB_DATA_DIR:-./.data/$${SUITECRM_PROJECT_NAME:-suitecrm}/mariadb}; \
	TS=$$(date +%Y%m%d-%H%M%S); \
	[ -d "$$DATA_DIR" ] || { echo "No data dir $$DATA_DIR"; exit 0; }; \
	BKP="$$DATA_DIR.bak-$$TS"; \
	echo "⚠️  Moving $$DATA_DIR -> $$BKP"; \
	docker compose $(ENV_FILES) stop db >/dev/null 2>&1 || true; \
	mv "$$DATA_DIR" "$$BKP"; \
	mkdir -p "$$DATA_DIR"; \
	echo "✅ Done (backup: $$BKP)"

##@ Utils
.PHONY: db-info
db-info: ## Vypíše přístup k DB a otestuje spojení z hosta
	@echo "Host: 127.0.0.1"
	@echo "Port: $${SUITECRM_DB_PORT_HOST:-3308}"
	@echo "User: $${SUITECRM_DB_USER:-suitecrm}"
	@echo "Pass: $${SUITECRM_DB_PASSWORD:-secret}"
	@echo "DB:   $${SUITECRM_DB_NAME:-suitecrm_suitecrm}"
	@nc -vz 127.0.0.1 $${SUITECRM_DB_PORT_HOST:-3308} || true

##@ Setup

.PHONY: fresh
fresh: ## Kompletní fresh se self-heal DB, CLI instalací a migracemi
	@echo "🚨 Killing previous stack (containers, orphans)"
	- docker compose $(ENV_FILES) down --remove-orphans || true

	@echo "🧹 Freeing DB port if busy"
	- @PORT=$${SUITECRM_DB_PORT_HOST:-3308}; \
	  CID=$$(docker ps --format '{{.ID}} {{.Ports}}' | awk '/:'"$$PORT"'->/ {print $$1; exit}'); \
	  if [ -n "$$CID" ]; then echo "Stopping container using port $$PORT: $$CID"; docker stop "$$CID" >/devnull; fi

	@echo "🧹 Freeing well-known ports if busy (8025=Mailhog)"
	- @CID=$$(docker ps --format '{{.ID}} {{.Ports}}' | awk '/:8025->/ {print $$1}' | head -n1); \
	  if [ -n "$$CID" ]; then echo "Stopping container using 8025: $$CID"; docker stop $$CID >/dev/null; fi

	@echo "🚀 Building containers"
	docker compose $(ENV_FILES) build

	@echo "→ Starting infra"
	docker compose $(ENV_FILES) up -d db redis elasticsearch mailhog
	$(MAKE) db-up
	$(MAKE) db-wait
	$(MAKE) db-reset
	$(MAKE) db-ensure-user

	@echo "→ Starting app service"
	docker compose $(ENV_FILES) up -d app

	@echo "→ Waiting for app DB login (from app container)"
	bash ops/scripts/app-wait-db.sh

	@echo "→ SuiteCRM CLI install"
	bash ops/scripts/app-install.sh

	@echo "→ Composer install (inside app)"
	docker compose $(ENV_FILES) exec -T app bash -lc 'COMPOSER_MEMORY_LIMIT=-1 composer install --no-interaction'

	@echo "→ Bringing full stack up"
	docker compose $(ENV_FILES) up -d

	@echo "→ Doctrine migrations (optional)"
	docker compose $(ENV_FILES) exec -T app php bin/console doctrine:migrations:migrate -n || true

	@echo "✅ Fresh SuiteCRM ready at http://localhost:$${SUITECRM_APP_PORT:-8080}"

##@ Utils
.PHONY: kill-port
kill-port: ## Kill container/listener on a given host port OR by SERVICE (SERVICE=phpmyadmin|mailhog|app) or PORT=xxxx
	@set -e; \
	# 1) načti .env/.env.local (kvůli portům služeb)
	set -a; [ -f ./.env ] && . ./.env; [ -f ./.env.local ] && . ./.env.local; set +a; \
	# 2) rozlišení portu podle SERVICE/PORT
	if [ -n "$$SERVICE" ] 2>/dev/null; then \
		case "$$SERVICE" in \
			phpmyadmin) PORT="$${SUITECRM_PHPMYADMIN_PORT:-8081}" ;; \
			mailhog)    PORT="$${SUITECRM_MAILHOG_PORT_HOST:-8025}" ;; \
			app)        PORT="$${SUITECRM_APP_PORT:-8080}" ;; \
			*) echo "Unknown SERVICE='$$SERVICE'. Use SERVICE=phpmyadmin|mailhog|app or PORT=<num>"; exit 1 ;; \
		esac; \
	elif [ -n "$$PORT" ] 2>/dev/null; then \
		:; \
	else \
		echo "Set PORT=<num> or SERVICE=phpmyadmin|mailhog|app"; exit 1; \
	fi; \
	echo "→ Releasing port $$PORT"; \
	# 3) pokusně zastav compose službu, když odpovídá zvolenému portu
	if [ "$$SERVICE" = "phpmyadmin" ] 2>/dev/null; then \
		echo "  Trying: docker compose stop phpmyadmin"; \
		docker compose $(ENV_FILES) stop phpmyadmin >/dev/null 2>&1 || true; \
	fi; \
	# 4) najdi a zastav libovolný Docker kontejner, který port drží (běžící i exited)
	CID=$$(docker ps --format '{{.ID}} {{.Ports}}' | awk '/:'''$$PORT'''->/ {print $$1}' | head -n1); \
	if [ -n "$$CID" ]; then \
		echo "  Stopping Docker container on $$PORT: $$CID"; \
		docker stop "$$CID" >/dev/null || true; \
	fi; \
	# (pro jistotu ještě jednou – i mezi exited může být zombie proxy)
	CID_ALL=$$(docker ps -a --format '{{.ID}} {{.Ports}}' | awk '/:'''$$PORT'''->/ {print $$1}' | head -n1); \
	if [ -n "$$CID_ALL" ]; then \
		echo "  Removing Docker container bound to $$PORT: $$CID_ALL"; \
		docker rm -f "$$CID_ALL" >/dev/null || true; \
	fi; \
	# 5) zabij lokální proces naslouchající na portu (host)
	PID=$$(lsof -tiTCP:$$PORT -sTCP:LISTEN 2>/dev/null || true); \
	if [ -n "$$PID" ]; then \
		echo "  Killing local process $$PID on port $$PORT"; \
		kill $$PID || true; \
	else \
		echo "  No local process on $$PORT"; \
	fi; \
	echo "✅ Port $$PORT is free"


.PHONY: down-hard
down-hard: ## Stop + remove containers, networks, volumes
	docker compose $(ENV_FILES) down -v --remove-orphans || true

.PHONY: help
help: ## Zobrazí tuto nápovědu
	@awk 'BEGIN {FS = ":.*##"; printf "\nPoužití:\n  make \033[36m<cil>\033[0m\n"} /^[a-zA-Z0-9_.-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
