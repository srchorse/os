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

# Enable ufw on boot without trying to apply live kernel rules inside Cubic.
set_ufw_value /etc/ufw/ufw.conf ENABLED yes
set_ufw_value /etc/ufw/ufw.conf LOGLEVEL low

if [[ -f /usr/lib/systemd/system/ufw.service ]]; then
	ln -sf /usr/lib/systemd/system/ufw.service /etc/systemd/system/multi-user.target.wants/ufw.service
fi

# Apply the firewall immediately on a normal running system. In Cubic/chroot
# this may fail because kernel firewall hooks are not fully available yet.
if [[ -d /run/systemd/system ]]; then
	ufw reload || ufw --force enable || true
fi
