#!/bin/bash

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
	echo "Run this script as root." >&2
	exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SH_DIR="${SCRIPT_DIR}/sh"

source_part() {
	local name="$1"
	local path="${SH_DIR}/${name}.sh"

	if [[ ! -r "${path}" ]]; then
		echo "Missing required script: ${path}" >&2
		exit 1
	fi

	# shellcheck source=/dev/null
	. "${path}"
}

run_target_part() {
	local name="$1"
	local target_root="${2:-/}"
	local path="${SH_DIR}/${name}.sh"

	if [[ ! -r "${path}" ]]; then
		echo "Missing required script: ${path}" >&2
		exit 1
	fi

	bash "${path}" "${target_root}"
}

source_part setup
source_part base
source_part repo
source_part core
source_part firewall
source_part php
source_part mysql
source_part snap
source_part npm
source_part purge
source_part panel
source_part appearance

# Run the target-aware branding steps last against / because os.sh is intended
# for the active Cubic rootfs, where / is the image that will be packed.
run_target_part release /
run_target_part boot /
