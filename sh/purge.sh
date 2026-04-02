#!/bin/bash

# Remove the stock desktop applications that ship in the Ubuntu Cinnamon image
# but are not part of the SrcHorse target setup. These package names come from
# the Cubic manifests and the Noble apt metadata for the visible app names.
PURGE_PACKAGES=(
	gedit
	pidgin
	hexchat
	alacritty
	aisleriot
	gnome-2048
	brasero
	cheese
	gnome-chess
	firefox
	five-or-more
	four-in-a-row
	gnote
	hitori
	gnome-klotski
	gnome-mahjongg
	gnome-mines
	gnome-nibbles
	quadrapassel
	iagno
	rhythmbox
	gnome-robots
	sound-juicer
	gnome-sudoku
	swell-foop
	tali
	gnome-taquin
	gnome-tetravex
	thunderbird
	totem
)

# Firefox and Thunderbird are still snap-backed in Noble, so purging the debs
# is only half of the removal. Track the matching snaps separately and remove
# them on first boot, when snapd exists outside the Cubic build environment.
PURGE_SNAPS=(
	firefox
	thunderbird
)

if ((${#PURGE_PACKAGES[@]})); then
	apt-get purge -y "${PURGE_PACKAGES[@]}"
fi

if ((${#PURGE_SNAPS[@]})); then
	# Cubic cannot talk to snapd during the build, so write a first-boot cleanup
	# job that waits for snap seeding and then removes the seeded browser/mail snaps
	# from the installed machine. The done marker keeps the removal one-shot only.
	install -d -m 0755 /usr/local/sbin
	install -d -m 0755 /etc/systemd/system
	install -d -m 0755 /etc/systemd/system/multi-user.target.wants
	install -d -m 0755 /var/lib/os-sh

	cat <<'EOF' >/usr/local/sbin/purge-firstboot-snaps
#!/bin/bash

set -euo pipefail

exec >>/var/log/purge-firstboot-snaps.log 2>&1

if [[ -f /var/lib/os-sh/purge-firstboot-snaps.done ]]; then
	exit 0
fi

if ! command -v snap >/dev/null 2>&1; then
	touch /var/lib/os-sh/purge-firstboot-snaps.done
	exit 0
fi

for _ in $(seq 1 60); do
	if snap version >/dev/null 2>&1; then
		break
	fi
	sleep 5
done

if ! snap version >/dev/null 2>&1; then
	touch /var/lib/os-sh/purge-firstboot-snaps.done
	exit 0
fi

snap wait system seed.loaded || true

for snap_name in firefox thunderbird; do
	if snap list "${snap_name}" >/dev/null 2>&1; then
		snap remove --purge "${snap_name}" || true
	fi
done

touch /var/lib/os-sh/purge-firstboot-snaps.done
EOF
	chmod 0755 /usr/local/sbin/purge-firstboot-snaps

	cat <<'EOF' >/etc/systemd/system/purge-firstboot-snaps.service
[Unit]
Description=Remove seeded snaps that SrcHorse does not keep
After=network-online.target snapd.socket snapd.seeded.service
Wants=network-online.target snapd.socket snapd.seeded.service
ConditionPathExists=!/var/lib/os-sh/purge-firstboot-snaps.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/purge-firstboot-snaps

[Install]
WantedBy=multi-user.target
EOF

	ln -sf /etc/systemd/system/purge-firstboot-snaps.service /etc/systemd/system/multi-user.target.wants/purge-firstboot-snaps.service
fi
