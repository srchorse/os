#!/bin/bash

PHP_MODULES=(
	apcu
	ast
	bcmath
	bz2
	cli
	common
	curl
	decimal
	dev
	fpm
	gd
	grpc
	http
	igbinary
	imap
	intl
	mbstring
	memcached
	mysql
	oauth
	opcache
	pgsql
	protobuf
	ps
	pspell
	psr
	readline
	redis
	smbclient
	soap
	solr
	sqlite3
	ssh2
	tidy
	uploadprogress
	uuid
	xdebug
	xlswriter
	xml
	xmlrpc
	xsl
	yaml
	zip
)

PHP_PACKAGES=(
	php8.4
)

PHP_PACKAGES+=("${PHP_MODULES[@]/#/php8.4-}")

apt-get install -y "${PHP_PACKAGES[@]}"

a2enconf php8.4-fpm
a2enmod proxy_fcgi setenvif

# composer
EXPECTED_CHECKSUM="$(php -r "copy('https://composer.github.io/installer.sig', 'php://stdout');")"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [[ "${EXPECTED_CHECKSUM}" != "${ACTUAL_CHECKSUM}" ]]; then
	rm -f composer-setup.php
	echo "Composer installer checksum mismatch" >&2
	exit 1
fi

php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm -f composer-setup.php

COMPOSER_GLOBAL_HOME=/usr/local/share/composer
COMPOSER_GLOBAL_BIN="${COMPOSER_GLOBAL_HOME}/vendor/bin"

install -d -m 0755 "${COMPOSER_GLOBAL_HOME}"
install -d -m 0755 /etc/profile.d

cat <<'EOF' >/etc/profile.d/composer-global-bin.sh
#!/bin/sh
COMPOSER_GLOBAL_BIN="/usr/local/share/composer/vendor/bin"

case ":${PATH}:" in
	*:"${COMPOSER_GLOBAL_BIN}":*)
		;;
	*)
		export PATH="${COMPOSER_GLOBAL_BIN}:${PATH}"
		;;
esac
EOF
chmod 0644 /etc/profile.d/composer-global-bin.sh

export COMPOSER_HOME="${COMPOSER_GLOBAL_HOME}"
export COMPOSER_ALLOW_SUPERUSER=1
export PATH="${COMPOSER_GLOBAL_BIN}:${PATH}"

# symfony
curl -1sLf 'https://dl.cloudsmith.io/public/symfony/stable/setup.deb.sh' | bash
apt-get update
apt-get install -y symfony-cli

# drush
composer global require --no-interaction drush/drush
