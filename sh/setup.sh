#!/bin/bash

# These environment variables keep apt and maintainer scripts non-interactive
# during the image build, which prevents Cubic from hanging on prompts nobody
# can answer. RUNLEVEL is lowered so package hooks do not expect a full desktop.
export DEBIAN_FRONTEND=noninteractive
export RUNLEVEL=1

# Cubic behaves like a chroot, so service startups during package install often
# fail even when the package configuration should succeed. This policy script
# blocks most starts, but still allows Apache and PHP-FPM for intentional setup.
cat <<'EOF' >/usr/sbin/policy-rc.d
#!/bin/sh
case "${1:-}" in
	apache2|php8.4-fpm)
		exit 0
		;;
esac
exit 101
EOF
chmod 0755 /usr/sbin/policy-rc.d
trap 'rm -f /usr/sbin/policy-rc.d' EXIT

# These directories are created up front so later installs and first-boot tasks
# find the paths they expect, even in Cubic where runtime directories are thin.
# That prevents failures around Apache, apt keyrings, systemd links, and state.
install -d -m 0755 /etc/apt/keyrings
install -d -m 0755 /usr/share/keyrings
install -d -m 0755 /var/log/apache2
install -d -m 0755 -o www-data -g root /var/run/apache2
install -d -m 0755 -o www-data -g root /run/lock/apache2
install -d -m 0755 /usr/local/sbin
install -d -m 0755 /etc/systemd/system
install -d -m 0755 /etc/systemd/system/multi-user.target.wants
install -d -m 0755 /var/lib/os-sh