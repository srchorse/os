#!/bin/bash

# Install the standard Ubuntu firewall tools.
FIREWALL_PACKAGES=(
	gufw
	ufw
)

apt-get install -y "${FIREWALL_PACKAGES[@]}"

set_ufw_value() {
	local file="$1"
	local key="$2"
	local value="$3"

	if grep -q "^${key}=" "${file}"; then
		sed -i "s#^${key}=.*#${key}=${value}#" "${file}"
	else
		printf '%s=%s\n' "${key}" "${value}" >>"${file}"
	fi
}

# Harden the desktop firewall defaults: block unsolicited inbound traffic,
# allow normal outbound traffic for web, git, package managers, and updates.
set_ufw_value /etc/default/ufw IPV6 yes
set_ufw_value /etc/default/ufw DEFAULT_INPUT_POLICY '"DROP"'
set_ufw_value /etc/default/ufw DEFAULT_OUTPUT_POLICY '"ACCEPT"'
set_ufw_value /etc/default/ufw DEFAULT_FORWARD_POLICY '"DROP"'
set_ufw_value /etc/default/ufw DEFAULT_APPLICATION_POLICY '"SKIP"'
set_ufw_value /etc/default/ufw MANAGE_BUILTINS no

# Persist the firewall defaults across reboots.
set_ufw_value /etc/ufw/ufw.conf ENABLED yes
set_ufw_value /etc/ufw/ufw.conf LOGLEVEL low

# Apply the firewall immediately on the running machine and make sure the ufw
# service is enabled through the normal systemd path when systemd is present.
ufw reload || ufw --force enable || true

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
	systemctl enable --now ufw.service >/dev/null 2>&1 || true
fi
