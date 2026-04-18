#!/bin/bash

# Remove the stock desktop applications that are not part of the SrcHorse
# target workstation. This keeps the upgraded machine closer to the desired set.
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

# Firefox and Thunderbird may also exist as snaps on Ubuntu 24.04, so remove
# those immediately after the main snap install step has brought snapd online.
PURGE_SNAPS=(
	firefox
	thunderbird
)

if ((${#PURGE_PACKAGES[@]})); then
	apt-get purge -y "${PURGE_PACKAGES[@]}"
fi

if command -v snap >/dev/null 2>&1 && ((${#PURGE_SNAPS[@]})); then
	wait_for_snapd_ready

	for snap_name in "${PURGE_SNAPS[@]}"; do
		if snap list "${snap_name}" >/dev/null 2>&1; then
			snap remove --purge "${snap_name}"
		fi
	done
fi
