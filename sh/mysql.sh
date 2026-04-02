#!/bin/bash

cat <<'EOF' >/usr/local/sbin/install-firstboot-mysql
#!/bin/bash

set -euo pipefail

exec >>/var/log/install-firstboot-mysql.log 2>&1

if [[ -f /var/lib/os-sh/install-firstboot-mysql.done ]]; then
	exit 0
fi

if dpkg -s mysql-client mysql-server >/dev/null 2>&1; then
	touch /var/lib/os-sh/install-firstboot-mysql.done
	exit 0
fi

apt-get -o DPkg::Lock::Timeout=300 update
apt-get -o DPkg::Lock::Timeout=300 install -y mysql-client mysql-server

touch /var/lib/os-sh/install-firstboot-mysql.done
EOF
chmod 0755 /usr/local/sbin/install-firstboot-mysql

cat <<'EOF' >/etc/systemd/system/install-firstboot-mysql.service
[Unit]
Description=Install MySQL packages on first boot
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/os-sh/install-firstboot-mysql.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/install-firstboot-mysql

[Install]
WantedBy=multi-user.target
EOF

ln -sf /etc/systemd/system/install-firstboot-mysql.service /etc/systemd/system/multi-user.target.wants/install-firstboot-mysql.service
