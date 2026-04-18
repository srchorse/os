#!/bin/bash

# Install the requested desktop and tooling snaps during the main run. Existing
# installs are refreshed so the managed set lands on current revisions.
DIRECT_SNAPS=(
	discord
	plex-desktop
	slack
	spotify
	teams-for-linux
	mc-installer
	snap-store
	trello-cli
	canonical-livepatch
)

CLASSIC_SNAPS=(
	flutter
	blender
)

wait_for_snapd_ready

for snap_name in "${DIRECT_SNAPS[@]}"; do
	if snap list "${snap_name}" >/dev/null 2>&1; then
		snap refresh "${snap_name}"
	else
		snap install "${snap_name}"
	fi
done

for snap_name in "${CLASSIC_SNAPS[@]}"; do
	if snap list "${snap_name}" >/dev/null 2>&1; then
		snap refresh "${snap_name}"
	else
		snap install "${snap_name}" --classic
	fi
done
