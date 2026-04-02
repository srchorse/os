#!/bin/bash

set -euo pipefail

TARGET_ROOT="${1:-/}"

# Final release branding for the installed image.
RELEASE_NAME="Ubuntu Src Horse"
OLD_BRAND_FRAGMENT="Cinnamon"
INTERMEDIATE_REMIX_NAME="Src Horse Remix"
INTERMEDIATE_HYPHENATED_NAME="Ubuntu-Src Horse"
BRANDING_RELATIVE_ROOTS=(
	".disk"
	"EFI"
	"boot"
	"boot/efi"
	"casper"
	"cdrom"
	"isodevice"
	"etc/default/grub"
	"etc/grub.d"
	"usr/share/gnome-background-properties"
	"usr/share/metainfo"
	"usr/share/plymouth"
)

usage() {
	cat <<'EOF'
Usage: ./sh/release.sh [target-root]

Examples:
  ./sh/release.sh
  ./sh/release.sh /
  ./sh/release.sh ~/www/os/custom-disk
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
	local base="$1"

	if [[ "${base}" == "/" ]]; then
		return 1
	fi

	if [[ "${base##*/}" != "custom-root" ]]; then
		return 1
	fi

	printf '%s\n' "$(dirname "${base}")"
}

join_target_path() {
	local base="$1"
	local relative="$2"

	if [[ "${base}" == "/" ]]; then
		printf '/%s\n' "${relative}"
	else
		printf '%s/%s\n' "${base%/}" "${relative}"
	fi
}

build_release_label() {
	local current_value="$1"

	if [[ "${current_value}" == "${RELEASE_NAME}"* ]]; then
		printf '%s\n' "${current_value}"
		return 0
	fi

	if [[ "${current_value}" == Ubuntu* ]]; then
		printf '%s%s\n' "${RELEASE_NAME}" "${current_value#Ubuntu}"
		return 0
	fi

	printf '%s\n' "${RELEASE_NAME}"
}

set_or_add_line() {
	local file="$1"
	local key="$2"
	local value="$3"

	[[ -f "${file}" ]] || return 0

	if grep -q "^${key}=" "${file}"; then
		sed -i "s#^${key}=.*#${key}=${value}#" "${file}"
	else
		printf '%s=%s\n' "${key}" "${value}" >>"${file}"
	fi
}

require_writable_target_path() {
	local path="$1"
	local description="$2"
	local parent

	[[ -e "${path}" ]] || return 0
	[[ "${EUID}" -eq 0 ]] && return 0

	parent="$(dirname "${path}")"

	# release.sh mixes shell redirections and sed/perl in-place rewrites, so a
	# direct invocation against a root-owned custom-root tree needs both the
	# file and its containing directory writable before the first edit begins.
	if [[ -d "${path}" && ! -w "${path}" ]]; then
		echo "Run this script as root when targeting ${TARGET_ROOT}; ${description} directory is not writable: ${path}" >&2
		exit 1
	fi

	if [[ -f "${path}" && ! -w "${path}" ]]; then
		echo "Run this script as root when targeting ${TARGET_ROOT}; ${description} is not writable: ${path}" >&2
		exit 1
	fi

	if [[ ! -w "${parent}" ]]; then
		echo "Run this script as root when targeting ${TARGET_ROOT}; parent directory is not writable for ${description}: ${parent}" >&2
		exit 1
	fi
}

ensure_release_target_writable() {
	local base="$1"
	local relative_root
	local absolute_root

	# The local wrapper usually handles sudo escalation, but direct runs of this
	# sh against a restored rootfs should still fail with a clear privilege
	# error instead of surfacing a raw sed temporary-file permission problem.
	require_writable_target_path "$(join_target_path "${base}" "etc/os-release")" "os-release metadata"
	require_writable_target_path "$(join_target_path "${base}" "usr/lib/os-release")" "usr/lib os-release metadata"
	require_writable_target_path "$(join_target_path "${base}" "etc/lsb-release")" "lsb-release metadata"
	require_writable_target_path "$(join_target_path "${base}" "etc/upstream-release/lsb-release")" "upstream lsb-release metadata"
	require_writable_target_path "$(join_target_path "${base}" "etc/issue")" "console banner"
	require_writable_target_path "$(join_target_path "${base}" "etc/issue.net")" "network banner"
	require_writable_target_path "$(join_target_path "${base}" "etc/default/grub")" "grub defaults"
	require_writable_target_path "$(join_target_path "${base}" "etc/grub.d/10_linux")" "grub linux script"

	for relative_root in "${BRANDING_RELATIVE_ROOTS[@]}"; do
		absolute_root="$(join_target_path "${base}" "${relative_root}")"
		[[ -e "${absolute_root}" ]] || continue
		require_writable_target_path "${absolute_root}" "branding root ${relative_root}"
	done
}

find_branding_files() {
	local base="$1"
	local relative_root
	local absolute_root

	for relative_root in "${BRANDING_RELATIVE_ROOTS[@]}"; do
		absolute_root="$(join_target_path "${base}" "${relative_root}")"
		[[ -e "${absolute_root}" ]] || continue

		grep -RIl \
			--binary-files=without-match \
			-e "${OLD_BRAND_FRAGMENT}" \
			-e "${INTERMEDIATE_REMIX_NAME}" \
			-e "${INTERMEDIATE_HYPHENATED_NAME}" \
			"${absolute_root}" 2>/dev/null || true
	done | sort -u
}

replace_visible_branding() {
	local base="$1"
	local file

	# The first pass keeps the original perl rewrite, but it now works against
	# one explicit target root. That lets the same script brand Cubic's live /
	# tree and a host-side disk tree like ~/www/os/custom-disk the same way.
	while IFS= read -r file; do
		perl -0pi -e "s/\Q${OLD_BRAND_FRAGMENT}\E/Src Horse/g; s/\Q${INTERMEDIATE_REMIX_NAME}\E/Src Horse/g; s/\Q${INTERMEDIATE_HYPHENATED_NAME}\E/${RELEASE_NAME}/g" \
			"${file}"
	done < <(find_branding_files "${base}")
}

replace_visible_branding_with_sed() {
	local base="$1"
	local file

	# The second pass repeats the same cleanup with sed so the release rename
	# does not depend on perl alone. It also catches intermediate strings left
	# behind after the broad Cinnamon -> Src Horse replacement.
	while IFS= read -r file; do
		sed -i \
			-e 's/Cinnamon/Src Horse/g' \
			-e 's/Src Horse Remix/Src Horse/g' \
			-e 's/Ubuntu-Src Horse/Ubuntu Src Horse/g' \
			"${file}"
	done < <(find_branding_files "${base}")
}

replace_visible_branding_with_python() {
	local base="$1"
	local relative_root
	local absolute_root

	# This mirrors the recursive content-rewrite style of ~/bin/str. It walks
	# each branding root, skips binary and non-UTF-8 files, and rewrites text
	# in place without renaming packaged asset paths inside the target tree.
	command -v python3 >/dev/null 2>&1 || return 0

	for relative_root in "${BRANDING_RELATIVE_ROOTS[@]}"; do
		absolute_root="$(join_target_path "${base}" "${relative_root}")"
		[[ -e "${absolute_root}" ]] || continue

		python3 - "${absolute_root}" "${OLD_BRAND_FRAGMENT}" "${INTERMEDIATE_REMIX_NAME}" "${INTERMEDIATE_HYPHENATED_NAME}" "${RELEASE_NAME}" <<'PY'
from __future__ import annotations

import os
import sys
from pathlib import Path

DEFAULT_IGNORED_DIRS = {".git", ".hg", ".svn", "node_modules", "vendor", ".venv", "venv", "__pycache__"}

root = Path(sys.argv[1])
old_brand_fragment = sys.argv[2]
intermediate_remix_name = sys.argv[3]
intermediate_hyphenated_name = sys.argv[4]
release_name = sys.argv[5]


def is_binary(data: bytes) -> bool:
    return b"\0" in data


for dirpath, dirnames, filenames in os.walk(root, topdown=True):
    dirnames[:] = [name for name in dirnames if name not in DEFAULT_IGNORED_DIRS]
    base = Path(dirpath)

    for name in filenames:
        path = base / name

        try:
            data = path.read_bytes()
        except OSError:
            continue

        if is_binary(data):
            continue

        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue

        updated = text.replace(old_brand_fragment, "Src Horse")
        updated = updated.replace(intermediate_remix_name, "Src Horse")
        updated = updated.replace(intermediate_hyphenated_name, release_name)

        if updated != text:
            path.write_text(updated, encoding="utf-8")
PY
	done
}

replace_visible_branding_with_recursive_grep() {
	local base="$1"
	local file
	local tmp_file

	# The fourth pass lets recursive grep drive the rewrite and only touches
	# files that still match one of the branding fragments. That gives the
	# release step one more independent path before the ISO is rebuilt.
	while IFS= read -r file; do
		tmp_file="$(mktemp)"

		awk \
			-v old_brand_fragment="${OLD_BRAND_FRAGMENT}" \
			-v intermediate_remix_name="${INTERMEDIATE_REMIX_NAME}" \
			-v intermediate_hyphenated_name="${INTERMEDIATE_HYPHENATED_NAME}" \
			-v release_name="${RELEASE_NAME}" \
			'{
				gsub(old_brand_fragment, "Src Horse")
				gsub(intermediate_remix_name, "Src Horse")
				gsub(intermediate_hyphenated_name, release_name)
				print
			}' "${file}" > "${tmp_file}"

		if ! cmp -s "${file}" "${tmp_file}"; then
			cat "${tmp_file}" > "${file}"
		fi

		rm -f "${tmp_file}"
	done < <(find_branding_files "${base}")
}

apply_branding_passes() {
	local base="$1"

	replace_visible_branding "${base}"
	replace_visible_branding_with_sed "${base}"
	replace_visible_branding_with_python "${base}"
	replace_visible_branding_with_recursive_grep "${base}"
}

apply_release_to_target() {
	local base="$1"
	local os_release_path
	local usr_os_release_path
	local lsb_release_path
	local upstream_lsb_release_path
	local issue_path
	local issue_net_path
	local default_grub_path
	local grub_linux_path
	local pretty_release_name
	local lsb_release_value
	local lsb_codename_value
	local lsb_description

	if [[ "${base}" == "/" && "${EUID}" -ne 0 ]]; then
		echo "Run this script as root when targeting /." >&2
		exit 1
	fi

	os_release_path="$(join_target_path "${base}" "etc/os-release")"
	usr_os_release_path="$(join_target_path "${base}" "usr/lib/os-release")"
	lsb_release_path="$(join_target_path "${base}" "etc/lsb-release")"
	upstream_lsb_release_path="$(join_target_path "${base}" "etc/upstream-release/lsb-release")"
	issue_path="$(join_target_path "${base}" "etc/issue")"
	issue_net_path="$(join_target_path "${base}" "etc/issue.net")"
	default_grub_path="$(join_target_path "${base}" "etc/default/grub")"
	grub_linux_path="$(join_target_path "${base}" "etc/grub.d/10_linux")"

	ensure_release_target_writable "${base}"

	# If the target has a normal root filesystem layout, update the core release
	# metadata there as well. Pure disk trees like custom-disk skip this block
	# and still get the broad branding passes across GRUB and ISO metadata.
	if [[ ! -r "${os_release_path}" ]]; then
		apply_branding_passes "${base}"
		return 0
	fi

	# shellcheck source=/etc/os-release
	. "${os_release_path}"

	pretty_release_name="$(build_release_label "${PRETTY_NAME:-Ubuntu}")"
	lsb_release_value="${VERSION_ID}"
	lsb_codename_value="${VERSION_CODENAME:-${UBUNTU_CODENAME:-noble}}"
	lsb_description="${pretty_release_name}"

	set_or_add_line "${os_release_path}" NAME "\"${RELEASE_NAME}\""
	set_or_add_line "${os_release_path}" PRETTY_NAME "\"${pretty_release_name}\""
	set_or_add_line "${usr_os_release_path}" NAME "\"${RELEASE_NAME}\""
	set_or_add_line "${usr_os_release_path}" PRETTY_NAME "\"${pretty_release_name}\""

	if [[ -f "${lsb_release_path}" ]]; then
		# shellcheck source=/etc/lsb-release
		. "${lsb_release_path}"
		lsb_release_value="${DISTRIB_RELEASE:-${lsb_release_value}}"
		lsb_codename_value="${DISTRIB_CODENAME:-${lsb_codename_value}}"
		lsb_description="$(build_release_label "${DISTRIB_DESCRIPTION:-${pretty_release_name}}")"

		cat <<EOF >"${lsb_release_path}"
DISTRIB_ID="${RELEASE_NAME}"
DISTRIB_RELEASE=${lsb_release_value}
DISTRIB_CODENAME=${lsb_codename_value}
DISTRIB_DESCRIPTION="${lsb_description}"
EOF
	fi

	if [[ -f "${upstream_lsb_release_path}" ]]; then
		cat <<EOF >"${upstream_lsb_release_path}"
DISTRIB_ID="${RELEASE_NAME}"
DISTRIB_RELEASE=${lsb_release_value}
DISTRIB_CODENAME=${lsb_codename_value}
DISTRIB_DESCRIPTION="${lsb_description}"
EOF
	fi

	printf '%s \\n \\l\n' "${pretty_release_name}" >"${issue_path}"
	printf '%s\n' "${pretty_release_name}" >"${issue_net_path}"

	# Keep the generated rootfs GRUB config aligned with the new distributor
	# string before the broader branding passes sweep through /boot and friends.
	set_or_add_line "${default_grub_path}" GRUB_DISTRIBUTOR "\"${RELEASE_NAME}\""

	if [[ -f "${grub_linux_path}" ]] && ! grep -q 'Ubuntu\\ Src\\ Horse' "${grub_linux_path}"; then
		sed -i 's/Ubuntu|Kubuntu)/Ubuntu|Kubuntu|Ubuntu\\ Src\\ Horse)/' "${grub_linux_path}"
	fi

	if [[ "${base}" == "/" ]] && command -v update-grub >/dev/null 2>&1 && [[ -d /boot/grub ]]; then
		update-grub
	fi

	apply_branding_passes "${base}"
}

apply_release_to_related_targets() {
	local base="$1"
	local project_root
	local sibling_target

	apply_release_to_target "${base}"

	project_root="$(resolve_cubic_project_root "${base}")" || return 0

	# Keep host-side os_local branding aligned with the Cubic ISO tree as well.
	# Without this second pass, boot/grub and other disk metadata can continue to
	# show Ubuntu Cinnamon even after the unpacked rootfs is rebranded.
	for sibling_target in "${project_root}/source-disk" "${project_root}/custom-disk"; do
		[[ -d "${sibling_target}" ]] || continue
		if [[ ! -w "${sibling_target}" ]]; then
			echo "Skipping read-only sibling target: ${sibling_target}" >&2
			continue
		fi
		apply_release_to_target "${sibling_target}"
	done
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

	if [[ "${target_root}" != "/" && ! -d "${target_root}" ]]; then
		echo "Missing target root directory: ${target_root}" >&2
		exit 1
	fi

	# os.sh calls this inside Cubic against /, which is the active image root.
	# Running it locally can point at a disk tree path like custom-disk instead.
	apply_release_to_related_targets "${target_root}"
}

main "$@"
