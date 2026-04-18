#!/bin/bash

# Install the MySQL client and server immediately on the running system.
MYSQL_PACKAGES=(
	mysql-client
	mysql-server
)

apt-get install -y "${MYSQL_PACKAGES[@]}"
