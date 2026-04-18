#!/bin/bash

# Keep apt and package hooks non-interactive so the upgrader can run cleanly on
# an already booted Ubuntu machine without pausing for prompts.
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Create the directories that later repository setup and service packages expect
# to exist. Doing this up front keeps Apache and apt keyring setup predictable.
install -d -m 0755 /etc/apt/keyrings
install -d -m 0755 /usr/share/keyrings
install -d -m 0755 /var/log/apache2
install -d -m 0755 -o www-data -g root /var/run/apache2
install -d -m 0755 -o www-data -g root /run/lock/apache2
install -d -m 0755 /usr/local/sbin

# Snap operations happen during the main install now, so expose one shared wait
# helper that later parts can reuse before they install or remove snap packages.
wait_for_snapd_ready() {
	local attempts="${1:-60}"
	local attempt

	if ! command -v snap >/dev/null 2>&1; then
		echo "snap is not available on this system" >&2
		return 1
	fi

	if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
		systemctl enable --now snapd.socket snapd.service >/dev/null 2>&1 || true
	fi

	for attempt in $(seq 1 "${attempts}"); do
		if snap version >/dev/null 2>&1; then
			break
		fi
		sleep 2
	done

	if ! snap version >/dev/null 2>&1; then
		echo "snapd did not become ready in time" >&2
		return 1
	fi

	snap wait system seed.loaded >/dev/null 2>&1 || true
}
