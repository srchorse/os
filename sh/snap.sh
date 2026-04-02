#!/bin/bash

cat <<'EOF' >/usr/local/sbin/install-firstboot-snaps
#!/bin/bash

set -euo pipefail

exec >>/var/log/install-firstboot-snaps.log 2>&1

if [[ -f /var/lib/os-sh/install-firstboot-snaps.done ]]; then
	exit 0
fi

for _ in $(seq 1 60); do
	if snap version >/dev/null 2>&1; then
		break
	fi
	sleep 5
done

snap wait system seed.loaded

for snap_name in \
	discord \
	plex-desktop \
	slack \
	spotify \
	teams-for-linux \
	mc-installer \
	snap-store \
	trello-cli \
	canonical-livepatch
do
	snap list "${snap_name}" >/dev/null 2>&1 || snap install "${snap_name}"
done

snap list flutter >/dev/null 2>&1 || snap install flutter --classic
snap list blender >/dev/null 2>&1 || snap install blender --classic

touch /var/lib/os-sh/install-firstboot-snaps.done
EOF
chmod 0755 /usr/local/sbin/install-firstboot-snaps

cat <<'EOF' >/etc/systemd/system/install-firstboot-snaps.service
[Unit]
Description=Install requested snaps on first boot
After=network-online.target snapd.socket snapd.seeded.service
Wants=network-online.target snapd.socket snapd.seeded.service
ConditionPathExists=!/var/lib/os-sh/install-firstboot-snaps.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/install-firstboot-snaps

[Install]
WantedBy=multi-user.target
EOF

ln -sf /etc/systemd/system/install-firstboot-snaps.service /etc/systemd/system/multi-user.target.wants/install-firstboot-snaps.service