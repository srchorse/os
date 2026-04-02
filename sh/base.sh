#!/bin/bash

BASE_PACKAGES=(
	software-properties-common
	apt-transport-https
	ca-certificates
	curl
	gnupg
	git
	git-lfs
	zip
	gzip
	unzip
	7zip
	cmake
	jq
	wget
	nano
)

apt-get update
apt-get install -y "${BASE_PACKAGES[@]}"