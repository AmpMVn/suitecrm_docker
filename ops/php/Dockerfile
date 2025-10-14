# =========================
# FE stage (Yarn 4 / Corepack) — volitelný
# =========================
FROM node:20-alpine AS fe
ARG SKIP_FE=0
WORKDIR /fe
RUN corepack enable || true
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./
RUN if [ -f package.json ]; then \
      PM=$(node -p "require('./package.json').packageManager || ''"); \
      if [ -n "$PM" ] && echo "$PM" | grep -qi '^yarn@'; then \
        YVER=${PM#yarn@}; \
        (corepack prepare "yarn@$YVER" --activate || (npm i -g "yarn@$YVER" && ln -sf $(command -v yarn) /usr/local/bin/yarn)); \
      fi; \
    fi
COPY . .
RUN mkdir -p dist
RUN if [ "$SKIP_FE" = "1" ]; then \
      echo "Skipping FE build (SKIP_FE=1)"; \
    else \
      if [ -f yarn.lock ]; then \
        yarn --version && yarn install --immutable && (yarn build || true); \
      elif [ -f package-lock.json ]; then \
        npm ci && (npm run build || true); \
      elif [ -f pnpm-lock.yaml ]; then \
        npm i -g pnpm && pnpm i --frozen-lockfile && (pnpm build || true); \
      else \
        echo "No lockfile, skipping FE build"; \
      fi; \
    fi

# =========================
# PHP base (Alpine, PHP-FPM)
# =========================
FROM php:8.2-fpm-alpine AS phpbase

RUN apk add --no-cache \
      git bash unzip \
      icu-dev libzip-dev oniguruma-dev \
      libpng-dev libjpeg-turbo-dev libwebp-dev freetype-dev \
      openldap-dev \
      autoconf g++ make

RUN docker-php-ext-configure gd --with-jpeg --with-webp --with-freetype \
 && docker-php-ext-install -j"$(nproc)" gd intl mbstring zip opcache pdo_mysql mysqli \
 && docker-php-ext-configure ldap \
 && docker-php-ext-install -j"$(nproc)" ldap

RUN pecl install redis && docker-php-ext-enable redis
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# --- PHP ini (memory, opcache) + NEW: upload/post size ---
ENV MAIN_LOG_LEVEL=info \
    PHP_MEMORY_LIMIT=512M \
    PHP_UPLOAD_MAX_FILESIZE=20M \
    PHP_POST_MAX_SIZE=20M

RUN printf "memory_limit=%s\n" "$PHP_MEMORY_LIMIT" > /usr/local/etc/php/conf.d/zz-memory-limit.ini \
 && { \
      echo "opcache.memory_consumption=256"; \
      echo "opcache.interned_strings_buffer=16"; \
      echo "opcache.max_accelerated_files=20000"; \
      echo "realpath_cache_size=4096K"; \
      echo "realpath_cache_ttl=600"; \
    } > /usr/local/etc/php/conf.d/zz-performance.ini \
 && { \
      echo "upload_max_filesize=$PHP_UPLOAD_MAX_FILESIZE"; \
      echo "post_max_size=$PHP_POST_MAX_SIZE"; \
    } > /usr/local/etc/php/conf.d/zz-upload-size.ini

# =========================
# Build
# =========================
FROM phpbase AS build
WORKDIR /var/www/html
COPY . /var/www/html
COPY --from=fe /fe/dist /var/www/html/public/_fe
RUN composer install --no-dev --optimize-autoloader --no-interaction || true

# =========================
# Runtime
# =========================
FROM phpbase AS runtime
WORKDIR /var/www/html
COPY --from=build /var/www/html /var/www/html
RUN addgroup -g 1000 www && adduser -G www -g www -s /bin/sh -D www \
 && chown -R www:www /var/www/html
USER www
