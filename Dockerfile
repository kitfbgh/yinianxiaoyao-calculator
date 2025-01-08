ARG NODE_VERSION=22
ARG PHP_VERSION=8.4
FROM node:${NODE_VERSION}-alpine AS node
FROM dunglas/frankenphp:builder-php${PHP_VERSION}-alpine AS builder

# Copy xcaddy in the builder image
COPY --from=caddy:builder /usr/bin/xcaddy /usr/bin/xcaddy

# CGO must be enabled to build FrankenPHP
RUN CGO_ENABLED=1 \
    XCADDY_SETCAP=1 \
    XCADDY_GO_BUILD_FLAGS="-ldflags='-w -s' -tags=nobadger,nomysql,nopgx" \
    CGO_CFLAGS=$(php-config --includes) \
    CGO_LDFLAGS="$(php-config --ldflags) $(php-config --libs)" \
    xcaddy build \
        --output /usr/local/bin/frankenphp \
        --with github.com/dunglas/frankenphp=./ \
        --with github.com/dunglas/frankenphp/caddy=./caddy/ \
        --with github.com/dunglas/caddy-cbrotli \
        # Mercure and Vulcain are included in the official build, but feel free to remove them
        --with github.com/dunglas/mercure/caddy \
        --with github.com/dunglas/vulcain/caddy
        # Add extra Caddy modules here

FROM dunglas/frankenphp:php${PHP_VERSION}-alpine AS local

RUN apk update && apk add bash

# Replace the official binary by the one contained your custom modules
COPY --from=builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp

# Set timezone
ENV TZ=Asia/Taipei
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN install-php-extensions \
	bcmath soap zip opcache pcntl sockets \
    imagick \
    redis-6.1.0 \
    mongodb-1.20.1 \
    apcu-5.1.24 \
    igbinary-3.2.16 \
    amqp-2.1.2 \
    xdebug-3.4.0

# Copy PHP config files
COPY .dockerEnvFiles/php/conf.d/docker-php-ext-xdebug.ini /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
COPY .dockerEnvFiles/php/php.ini /usr/local/etc/php/php.ini

ARG GITHUB_TOKEN
ARG USER=www-data
# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Set github token for composer
RUN composer config -g github-oauth.github.com ${GITHUB_TOKEN}

# Install Nodejs
COPY --from=node /usr/lib /usr/lib
COPY --from=node /usr/local/lib /usr/local/lib
COPY --from=node /usr/local/include /usr/local/include
COPY --from=node /usr/local/bin /usr/local/bin

RUN \
	# Add additional capability to bind to port 80 and 443
	setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
    && chown -R ${USER} /var/www /config/caddy /data/caddy

USER ${USER}
WORKDIR /var/www/html
EXPOSE 8080

COPY package*.json ./
RUN npm install

# The base for local development environment
# FROM ubuntu:20.04 AS base

# ENV DEBIAN_FRONTEND=noninteractive

# RUN set -eux \
#     && apt update \
#     && apt-get install -yq --no-install-recommends \
#         curl apt-transport-https gnupg2 software-properties-common ca-certificates lsb-release \
#     # Add apt repo from ppa:ondrej/php
#     && add-apt-repository ppa:ondrej/php \
#     && apt update \
#     && apt-get install --no-install-recommends -yq \
#         pkg-config autoconf dpkg-dev file g++ libc-dev re2c \
#         netbase gzip zip unzip sqlite3 \
#         # Install PHP & extensions
#         php${PHP_VERSION}-dev php-pear php${PHP_VERSION}-bcmath php${PHP_VERSION}-curl php${PHP_VERSION}-mbstring php${PHP_VERSION}-sqlite3 \
#         php${PHP_VERSION}-opcache php${PHP_VERSION}-readline php${PHP_VERSION}-soap php${PHP_VERSION}-xml \
#         php${PHP_VERSION}-xmlrpc php${PHP_VERSION}-zip php${PHP_VERSION}-sockets php${PHP_VERSION}-cli \
#     # Nodejs 18.x
#     && curl -sL https://deb.nodesource.com/setup_18.x | bash -  \
#     && apt-get install -y --no-install-recommends \
#         nodejs \
#     # Clear
#     && apt autoremove -y \
#     && apt clean \
#     && rm -rf /var/lib/apt/lists/*

# # FrankenPHP
# RUN set -eux \
#     && curl https://frankenphp.dev/install.sh | bash \
#     && mv frankenphp /usr/local/bin/

# # Set timezone
# ENV TZ=Asia/Taipei
# RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# # Copy PHP config files
# COPY .dockerEnvFiles/php/conf.d/docker-php-ext-xdebug.ini /etc/php/${PHP_VERSION}/cli/conf.d/docker-php-ext-xdebug.ini
# COPY .dockerEnvFiles/php/php.ini /etc/php/${PHP_VERSION}/cli/php.ini

# # Local development environment
# FROM base AS local

# ARG GITHUB_TOKEN
# ARG USER=www-data

# RUN set -eux \
#     && pecl install xdebug-3.4.0

# # Install Composer
# COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# # Set github token for composer
# RUN composer config -g github-oauth.github.com ${GITHUB_TOKEN}

# # Copy dependencies
# COPY --from=node_modules /var/www/html/node_modules /var/www/html/node_modules

# RUN \
# 	# Add additional capability to bind to port 80 and 443
# 	setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
#     && chown -R ${USER} /var/www

# USER ${USER}
# WORKDIR /var/www/html
# EXPOSE 8080
