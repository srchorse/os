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

	# shellcheck source=/dev/null
	. "${path}"
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