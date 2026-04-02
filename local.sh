#!/bin/bash

set -euo pipefail

TARGET_ROOT="${1:-/}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SH_DIR="${SCRIPT_DIR}/sh"

usage() {
	cat <<'EOF'
Usage: ./local.sh [target-root]

Examples:
  ./local.sh
  ./local.sh /
  ./local.sh ~/www/os/custom-root
  (cd ~/www/os/custom-root && ~/www/os-github/local.sh .)
EOF
}

normalize_target_root() {
	local target_root="$1"

	if [[ "${target_root}" == "/" ]]; then
		printf '/\n'
		return 0
	fi

	if [[ "${target_root}" == "~/"* ]]; then
		target_root="${HOME}/${target_root#~/}"
	fi

	if command -v realpath >/dev/null 2>&1; then
		realpath -m "${target_root}"
		return 0
	fi

	printf '%s\n' "${target_root%/}"
}

resolve_cubic_project_root() {
	local target_root="$1"

	if [[ "${target_root}" == "/" ]]; then
		return 1
	fi

	if [[ "${target_root##*/}" != "custom-root" ]]; then
		return 1
	fi

	printf '%s\n' "$(dirname "${target_root}")"
}

target_requires_root() {
	local target_root="$1"
	local candidate
	local project_root
	local -a candidate_paths=(
		"${target_root}"
		"${target_root}/etc"
		"${target_root}/usr/lib"
		"${target_root}/usr/share/plymouth/themes"
	)

	if project_root="$(resolve_cubic_project_root "${target_root}")"; then
		candidate_paths+=(
			"${project_root}/source-disk/casper"
			"${project_root}/source-disk/casper/initrd"
			"${project_root}/custom-disk/casper"
			"${project_root}/custom-disk/casper/initrd.gz"
		)
	fi

	# Host-side forensic restores commonly leave the unpacked rootfs owned by
	# root. The Cubic local flow also needs to patch the sibling live casper
	# initrd, so detect either case before release.sh or boot.sh hits a write
	# path that requires elevation.
	for candidate in "${candidate_paths[@]}"; do
		[[ -e "${candidate}" ]] || continue

		if [[ ! -w "${candidate}" ]]; then
			return 0
		fi
	done

	return 1
}

reexec_with_sudo() {
	local target_root="$1"

	if ! command -v sudo >/dev/null 2>&1; then
		echo "Run this script as root when targeting ${target_root}." >&2
		exit 1
	fi

	echo "Target root is not writable as ${USER:-current user}; re-running with sudo." >&2
	exec sudo -- bash "${SCRIPT_DIR}/local.sh" "${target_root}"
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

main() {
	local target_root="${TARGET_ROOT}"

	case "${target_root}" in
		-h|--help|help)
			usage
			return 0
			;;
	esac

	target_root="$(normalize_target_root "${target_root}")"

	if [[ "${target_root}" == "/" && "${EUID}" -ne 0 ]]; then
		echo "Run this script as root when targeting /." >&2
		exit 1
	fi

	if [[ "${target_root}" != "/" && ! -d "${target_root}" ]]; then
		echo "Missing target root directory: ${target_root}" >&2
		exit 1
	fi

	# Keep os_local usable against a restored custom-root tree without forcing
	# the caller to remember a separate sudo wrapper.
	if [[ "${target_root}" != "/" && "${EUID}" -ne 0 ]] && target_requires_root "${target_root}"; then
		reexec_with_sudo "${target_root}"
	fi

	# Keep the local workflow intentionally simple: just apply the release and
	# boot asset changes to one already-unpacked rootfs tree. Cubic is
	# responsible for any later squashfs, initrd, or ISO rebuild steps.
	run_target_part release "${target_root}"
	run_target_part boot "${target_root}"
}

main "$@"
