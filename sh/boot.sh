#!/bin/bash

set -euo pipefail

TARGET_ROOT="${1:-/}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT_ASSET_DIR="${REPO_ROOT}/assets/boot"
BOOT_WORDMARK_SOURCE="${BOOT_ASSET_DIR}/ubuntu-cinnamon-boot-wordmark.png"
BOOT_LOGO_SOURCE="${BOOT_ASSET_DIR}/ubuntu-cinnamon-boot-logo.png"
SRC_HORSE_THEME_NAME="srchorse-spinner"
SRC_HORSE_THEME_RELATIVE_DIR="usr/share/plymouth/themes/${SRC_HORSE_THEME_NAME}"
SRC_HORSE_THEME_RELATIVE_PATH="${SRC_HORSE_THEME_RELATIVE_DIR}/${SRC_HORSE_THEME_NAME}.plymouth"
LEGACY_THEME_NAME="ubuntucinnamon-spinner"
LEGACY_THEME_RELATIVE_DIR="usr/share/plymouth/themes/${LEGACY_THEME_NAME}"
LEGACY_THEME_RELATIVE_PATH="${LEGACY_THEME_RELATIVE_DIR}/${LEGACY_THEME_NAME}.plymouth"
SPINNER_THEME_NAME="spinner"
SPINNER_THEME_RELATIVE_DIR="usr/share/plymouth/themes/${SPINNER_THEME_NAME}"
SPINNER_THEME_RELATIVE_PATH="${SPINNER_THEME_RELATIVE_DIR}/${SPINNER_THEME_NAME}.plymouth"
BGRT_THEME_NAME="bgrt"
BGRT_THEME_RELATIVE_DIR="usr/share/plymouth/themes/${BGRT_THEME_NAME}"
BGRT_THEME_RELATIVE_PATH="${BGRT_THEME_RELATIVE_DIR}/${BGRT_THEME_NAME}.plymouth"
DEFAULT_THEME_RELATIVE_PATH="usr/share/plymouth/themes/default.plymouth"
DEFAULT_ALTERNATIVE_RELATIVE_PATH="etc/alternatives/default.plymouth"
DEFAULT_THEME_PRIORITY="1000"
LIVE_INITRD_MARKER_NAME=".srchorse-initrd-overlay"
LIVE_INITRD_MARKER_RELATIVE_PATH="${SRC_HORSE_THEME_RELATIVE_DIR}/${LIVE_INITRD_MARKER_NAME}"

usage() {
	cat <<'EOF'
Usage: ./sh/boot.sh [target-root]

Examples:
  ./sh/boot.sh
  ./sh/boot.sh /
  ./sh/boot.sh ~/www/os/custom-root
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

join_target_path() {
	local base="$1"
	local relative="$2"

	if [[ "${base}" == "/" ]]; then
		printf '/%s\n' "${relative}"
	else
		printf '%s/%s\n' "${base%/}" "${relative}"
	fi
}

require_writable_target_path() {
	local path="$1"
	local description="$2"
	local parent

	[[ -e "${path}" ]] || return 0
	[[ "${EUID}" -eq 0 ]] && return 0

	parent="$(dirname "${path}")"

	# boot.sh writes regular files, rewrites theme metadata, and may append an
	# overlay archive into Cubic's casper initrd. Fail early with the path that
	# blocks the update instead of surfacing a lower-level install/cat error.
	if [[ -d "${path}" && ! -w "${path}" ]]; then
		echo "Run this script as root when targeting ${TARGET_ROOT}; ${description} directory is not writable: ${path}" >&2
		exit 1
	fi

	if [[ -L "${path}" ]]; then
		if [[ ! -w "${parent}" ]]; then
			echo "Run this script as root when targeting ${TARGET_ROOT}; parent directory is not writable for ${description}: ${parent}" >&2
			exit 1
		fi

		return 0
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

resolve_theme_payload_source_dir() {
	local base="$1"
	local legacy_dir
	local fallback_dir

	legacy_dir="$(join_target_path "${base}" "${LEGACY_THEME_RELATIVE_DIR}")"
	fallback_dir="$(join_target_path "${base}" "${SPINNER_THEME_RELATIVE_DIR}")"

	# Copy the existing spinner payload into a dedicated Src Horse theme so the
	# final splash no longer depends on mutating Ubuntu Cinnamon's theme in place.
	if [[ -d "${legacy_dir}" ]]; then
		printf '%s\n' "${legacy_dir}"
		return 0
	fi

	if [[ -d "${fallback_dir}" ]]; then
		printf '%s\n' "${fallback_dir}"
		return 0
	fi

	echo "Missing Plymouth spinner payload under target root: ${base}" >&2
	exit 1
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

resolve_live_initrd_paths() {
	local base="$1"
	local project_root
	local -a candidate_paths
	local candidate_path
	local mount_options

	project_root="$(resolve_cubic_project_root "${base}")" || return 1
	candidate_paths=(
		"${project_root}/source-disk/casper/initrd"
		"${project_root}/custom-disk/casper/initrd.gz"
	)

	for candidate_path in "${candidate_paths[@]}"; do
		[[ -f "${candidate_path}" ]] || continue

		# The exported live initrd under custom-disk is typically mode 0444, but on
		# Cubic's writable ext filesystem root can still replace it. Filtering with
		# shell -w skips that valid target and leaves the stock splash in place.
		# Only skip candidates that are mounted read-only, such as source-disk.
		if command -v findmnt >/dev/null 2>&1; then
			mount_options="$(findmnt -no OPTIONS -T "${candidate_path}" 2>/dev/null || true)"
			if [[ ",${mount_options}," == *,ro,* ]]; then
				echo "Skipping read-only live initrd mount: ${candidate_path}" >&2
				continue
			fi
		fi

		printf '%s\n' "${candidate_path}"
	done
}

detect_main_initrd_payload() {
	local initrd_path="$1"

	python3 - "${initrd_path}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_bytes()
magic = {b"070701", b"070702"}
offset = 0
payload_offset = None
compression = "unknown"

while offset + 110 <= len(data):
    while offset < len(data) and data[offset] == 0:
        offset += 1

    if offset + 6 > len(data):
        break

    payload_magic = data[offset:offset + 6]

    if payload_magic in magic:
        payload_offset = offset
        compression = "cpio"

        while offset + 110 <= len(data) and data[offset:offset + 6] in magic:
            header = data[offset:offset + 110]
            namesize = int(header[94:102], 16)
            filesize = int(header[54:62], 16)
            name = data[offset + 110:offset + 110 + namesize - 1]

            offset += 110 + namesize
            offset = (offset + 3) & ~3
            offset += filesize
            offset = (offset + 3) & ~3

            if name == b"TRAILER!!!":
                break

        continue

    payload_offset = offset

    if payload_magic.startswith(b"\x28\xb5\x2f\xfd"):
        compression = "zstd"
    elif payload_magic.startswith(b"\x1f\x8b"):
        compression = "gzip"
    elif payload_magic.startswith(b"\xfd7zXZ\x00"):
        compression = "xz"
    elif payload_magic.startswith(b"\x02\x21\x4c\x18") or payload_magic.startswith(b"\x04\x22\x4d\x18"):
        compression = "lz4"
    else:
        compression = "unknown"

    break

if payload_offset is None:
    payload_offset = 0

print(f"{payload_offset}:{compression}")
PY
}

decompress_initrd_payload() {
	local compression="$1"

	case "${compression}" in
		zstd)
			zstd -d -q -c
			;;
		gzip)
			gzip -d -c
			;;
		xz)
			xz -d -c
			;;
		lz4)
			lz4 -d -c
			;;
		cpio)
			cat
			;;
		*)
			echo "Unsupported live initrd payload compression: ${compression}" >&2
			exit 1
			;;
	esac
}

compress_initrd_payload() {
	local compression="$1"

	case "${compression}" in
		zstd)
			zstd -19 -q
			;;
		gzip)
			gzip -9 -c
			;;
		xz)
			xz -9 -c
			;;
		lz4)
			lz4 -l -9
			;;
		cpio)
			cat
			;;
		*)
			echo "Unsupported live initrd payload compression: ${compression}" >&2
			exit 1
			;;
	esac
}

update_md5sum_entry() {
	local md5sum_path="$1"
	local relative_path="$2"
	local source_path="$3"
	local checksum
	local tmp_path

	[[ -f "${md5sum_path}" ]] || return 0
	[[ -f "${source_path}" ]] || return 0

	checksum="$(md5sum "${source_path}" | awk '{print $1}')"
	tmp_path="$(mktemp)"

	awk -v checksum="${checksum}" -v relative_path="${relative_path}" '
		$2 == relative_path {
			print checksum "  " relative_path
			found = 1
			next
		}
		{ print }
		END {
			if (!found) {
				print checksum "  " relative_path
			}
		}
	' "${md5sum_path}" > "${tmp_path}"

	install -m 0644 "${tmp_path}" "${md5sum_path}"
	rm -f "${tmp_path}"
}

write_theme_file() {
	local target_file="$1"
	local image_dir_name="$2"

	cat <<EOF >"${target_file}"
[Plymouth Theme]
Name=Ubuntu Src Horse Spinner
Description=Hardcoded Src Horse splash theme using only the repo boot assets.
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/${image_dir_name}
ScriptFile=/usr/share/plymouth/themes/${image_dir_name}/${image_dir_name}.script
EOF
}

write_theme_script() {
	local target_file="$1"

	cat <<'EOF' >"${target_file}"
Window.SetBackgroundTopColor(0.0, 0.0, 0.0);
Window.SetBackgroundBottomColor(0.0, 0.0, 0.0);

window_width = Window.GetWidth();
window_height = Window.GetHeight();
small_dimension = Math.Min(window_width, window_height);

logo_image = Image("logo.png");
logo_target_width = small_dimension * 0.23;
logo_scale = logo_target_width / logo_image.GetWidth();
logo_image = logo_image.Scale(logo_image.GetWidth() * logo_scale,
                              logo_image.GetHeight() * logo_scale);
logo_sprite = Sprite(logo_image);

wordmark_image = Image("wordmark.png");
wordmark_target_width = small_dimension * 0.50;
wordmark_scale = wordmark_target_width / wordmark_image.GetWidth();
wordmark_image = wordmark_image.Scale(wordmark_image.GetWidth() * wordmark_scale,
                                      wordmark_image.GetHeight() * wordmark_scale);
wordmark_sprite = Sprite(wordmark_image);

gap = small_dimension * 0.045;
stack_height = logo_image.GetHeight() + gap + wordmark_image.GetHeight();
stack_top = Window.GetY() + Window.GetHeight() * 0.5 - stack_height * 0.5;

logo_x = Window.GetX() + Window.GetWidth() * 0.5 - logo_image.GetWidth() * 0.5;
logo_y = stack_top;
wordmark_x = Window.GetX() + Window.GetWidth() * 0.5 - wordmark_image.GetWidth() * 0.5;
wordmark_y = logo_y + logo_image.GetHeight() + gap;

logo_sprite.SetPosition(logo_x, logo_y, 10);
wordmark_sprite.SetPosition(wordmark_x, wordmark_y, 10);
EOF
}

reset_theme_dir() {
	local theme_dir="$1"

	rm -rf "${theme_dir}"
	install -d -m 0755 "${theme_dir}"
}

install_minimal_theme_dir() {
	local theme_dir="$1"
	local theme_name="$2"

	reset_theme_dir "${theme_dir}"
	install -m 0644 "${BOOT_WORDMARK_SOURCE}" "${theme_dir}/wordmark.png"
	install -m 0644 "${BOOT_LOGO_SOURCE}" "${theme_dir}/logo.png"
	write_theme_file "${theme_dir}/${theme_name}.plymouth" "${theme_name}"
	write_theme_script "${theme_dir}/${theme_name}.script"
}

ensure_boot_target_writable() {
	local base="$1"
	local source_dir
	local src_horse_theme_dir
	local legacy_theme_dir
	local spinner_theme_dir
	local bgrt_theme_dir
	local default_theme_path
	local default_alternative_path
	local default_alternative_state_path
	local live_initrd_path

	source_dir="$(resolve_theme_payload_source_dir "${base}")"
	src_horse_theme_dir="$(join_target_path "${base}" "${SRC_HORSE_THEME_RELATIVE_DIR}")"
	legacy_theme_dir="$(join_target_path "${base}" "${LEGACY_THEME_RELATIVE_DIR}")"
	spinner_theme_dir="$(join_target_path "${base}" "${SPINNER_THEME_RELATIVE_DIR}")"
	bgrt_theme_dir="$(join_target_path "${base}" "${BGRT_THEME_RELATIVE_DIR}")"
	default_theme_path="$(join_target_path "${base}" "${DEFAULT_THEME_RELATIVE_PATH}")"
	default_alternative_path="$(join_target_path "${base}" "${DEFAULT_ALTERNATIVE_RELATIVE_PATH}")"
	default_alternative_state_path="$(join_target_path "${base}" "var/lib/dpkg/alternatives/default.plymouth")"

	require_writable_target_path "${source_dir}" "Plymouth spinner payload"
	require_writable_target_path "${src_horse_theme_dir}" "Src Horse Plymouth theme directory"
	require_writable_target_path "${spinner_theme_dir}" "spinner Plymouth theme directory"
	require_writable_target_path "${bgrt_theme_dir}" "BGRT Plymouth theme directory"
	require_writable_target_path "${default_theme_path}" "default Plymouth theme file"
	require_writable_target_path "${default_alternative_path}" "default Plymouth alternative link"
	require_writable_target_path "${default_alternative_state_path}" "default Plymouth alternative state"

	if [[ -d "${legacy_theme_dir}" ]]; then
		require_writable_target_path "${legacy_theme_dir}" "legacy Plymouth theme directory"
	fi

	while IFS= read -r live_initrd_path; do
		require_writable_target_path "${live_initrd_path}" "live casper initrd"
	done < <(resolve_live_initrd_paths "${base}" || true)
}

install_src_horse_theme() {
	local base="$1"
	local src_horse_theme_dir
	local legacy_theme_dir
	local spinner_theme_dir
	local bgrt_theme_dir
	local src_horse_theme_path
	local legacy_theme_path
	local spinner_theme_path
	local bgrt_theme_path
	local default_theme_path
	local default_alternative_path

	src_horse_theme_dir="$(join_target_path "${base}" "${SRC_HORSE_THEME_RELATIVE_DIR}")"
	legacy_theme_dir="$(join_target_path "${base}" "${LEGACY_THEME_RELATIVE_DIR}")"
	spinner_theme_dir="$(join_target_path "${base}" "${SPINNER_THEME_RELATIVE_DIR}")"
	bgrt_theme_dir="$(join_target_path "${base}" "${BGRT_THEME_RELATIVE_DIR}")"
	src_horse_theme_path="$(join_target_path "${base}" "${SRC_HORSE_THEME_RELATIVE_PATH}")"
	legacy_theme_path="$(join_target_path "${base}" "${LEGACY_THEME_RELATIVE_PATH}")"
	spinner_theme_path="$(join_target_path "${base}" "${SPINNER_THEME_RELATIVE_PATH}")"
	bgrt_theme_path="$(join_target_path "${base}" "${BGRT_THEME_RELATIVE_PATH}")"
	default_theme_path="$(join_target_path "${base}" "${DEFAULT_THEME_RELATIVE_PATH}")"
	default_alternative_path="$(join_target_path "${base}" "${DEFAULT_ALTERNATIVE_RELATIVE_PATH}")"

	# Replace every reachable theme path with the same minimal script theme so
	# Plymouth only ever renders the repo assets, never packaged Cinnamon frames.
	install_minimal_theme_dir "${src_horse_theme_dir}" "${SRC_HORSE_THEME_NAME}"
	install_minimal_theme_dir "${legacy_theme_dir}" "${LEGACY_THEME_NAME}"
	install_minimal_theme_dir "${spinner_theme_dir}" "${SPINNER_THEME_NAME}"
	install_minimal_theme_dir "${bgrt_theme_dir}" "${BGRT_THEME_NAME}"

	install -d -m 0755 "$(dirname "${default_theme_path}")"
	write_theme_file "${default_theme_path}" "${SRC_HORSE_THEME_NAME}"

	install -d -m 0755 "$(dirname "${default_alternative_path}")"
	ln -snf "/usr/share/plymouth/themes/${SRC_HORSE_THEME_NAME}/${SRC_HORSE_THEME_NAME}.plymouth" "${default_alternative_path}"

	# Keep the alternatives database aligned with the hardcoded default so the
	# initramfs hook sees the same theme selection during any later rebuild.
	if command -v update-alternatives >/dev/null 2>&1; then
		local -a alternative_command=(update-alternatives)

		if [[ "${base}" != "/" ]]; then
			alternative_command+=(--root "${base}")
		fi

		"${alternative_command[@]}" --quiet --force \
			--install "/usr/share/plymouth/themes/default.plymouth" "default.plymouth" \
			"/usr/share/plymouth/themes/${BGRT_THEME_NAME}/${BGRT_THEME_NAME}.plymouth" 110
		"${alternative_command[@]}" --quiet --force \
			--install "/usr/share/plymouth/themes/default.plymouth" "default.plymouth" \
			"/usr/share/plymouth/themes/${LEGACY_THEME_NAME}/${LEGACY_THEME_NAME}.plymouth" 150
		"${alternative_command[@]}" --quiet --force \
			--install "/usr/share/plymouth/themes/default.plymouth" "default.plymouth" \
			"/usr/share/plymouth/themes/${SRC_HORSE_THEME_NAME}/${SRC_HORSE_THEME_NAME}.plymouth" "${DEFAULT_THEME_PRIORITY}"
		"${alternative_command[@]}" --quiet \
			--set "default.plymouth" "/usr/share/plymouth/themes/${SRC_HORSE_THEME_NAME}/${SRC_HORSE_THEME_NAME}.plymouth"
	fi
}

live_initrd_payload_has_src_horse_marker() {
	local initrd_path="$1"
	local payload_info
	local payload_offset
	local payload_compression

	payload_info="$(detect_main_initrd_payload "${initrd_path}")"
	payload_offset="${payload_info%%:*}"
	payload_compression="${payload_info#*:}"

	if [[ "${payload_compression}" == "unknown" ]]; then
		echo "Unsupported live initrd payload format in ${initrd_path}" >&2
		exit 1
	fi

	# cpio --to-stdout is not a reliable existence probe here: on Cubic's live
	# initrd it can exit 0 even when the requested path is absent, which makes the
	# caller skip the rebuild and leaves the stock Ubuntu Cinnamon payload in
	# place. List the archive members instead and require an exact marker match.
	tail -c "+$((payload_offset + 1))" "${initrd_path}" \
		| decompress_initrd_payload "${payload_compression}" \
		| cpio --quiet -it 2>/dev/null \
		| grep -Fxq "${LIVE_INITRD_MARKER_RELATIVE_PATH}"
}

rebuild_live_initrd_payload() {
	local base="$1"
	local initrd_path="$2"
	local payload_info
	local payload_offset
	local payload_compression
	local marker_path
	local tmp_dir
	local prefix_path
	local payload_dir
	local new_payload_path
	local new_initrd_path
	local payload_theme_dir
	local payload_legacy_dir
	local payload_spinner_dir
	local payload_bgrt_dir
	local payload_default_dir

	if ! command -v cpio >/dev/null 2>&1; then
		echo "Missing required command: cpio" >&2
		exit 1
	fi

	payload_info="$(detect_main_initrd_payload "${initrd_path}")"
	payload_offset="${payload_info%%:*}"
	payload_compression="${payload_info#*:}"

	if [[ "${payload_compression}" == "unknown" ]]; then
		echo "Unsupported live initrd payload format in ${initrd_path}" >&2
		exit 1
	fi

	tmp_dir="$(mktemp -d)"
	prefix_path="${tmp_dir}/prefix.bin"
	payload_dir="${tmp_dir}/payload"
	new_payload_path="${tmp_dir}/payload.new"
	new_initrd_path="${tmp_dir}/initrd.new"
	payload_theme_dir="${payload_dir}/${SRC_HORSE_THEME_RELATIVE_DIR}"
	payload_legacy_dir="${payload_dir}/${LEGACY_THEME_RELATIVE_DIR}"
	payload_spinner_dir="${payload_dir}/${SPINNER_THEME_RELATIVE_DIR}"
	payload_bgrt_dir="${payload_dir}/${BGRT_THEME_RELATIVE_DIR}"
	payload_default_dir="$(dirname "${payload_dir}/${DEFAULT_THEME_RELATIVE_PATH}")"
	marker_path="${payload_dir}/${LIVE_INITRD_MARKER_RELATIVE_PATH}"

	# Cubic's live ISO boots from custom-disk/casper/initrd.gz, not directly from
	# custom-root. Rebuild the real compressed initramfs payload in place so the
	# Src Horse theme is baked into the exact archive QEMU boots, not appended as
	# an extra member that the live boot path may ignore.
	dd if="${initrd_path}" of="${prefix_path}" bs=1 count="${payload_offset}" status=none
	install -d -m 0755 "${payload_dir}"

	tail -c "+$((payload_offset + 1))" "${initrd_path}" \
		| decompress_initrd_payload "${payload_compression}" \
		| (
			cd "${payload_dir}"
			cpio -id --quiet
		)

	reset_theme_dir "${payload_theme_dir}"
	reset_theme_dir "${payload_legacy_dir}"
	reset_theme_dir "${payload_spinner_dir}"
	reset_theme_dir "${payload_bgrt_dir}"
	install -d -m 0755 "${payload_default_dir}"

	# Rebuild the live initrd theme payload directly from repo assets so Cubic's
	# later export steps cannot pull the old Ubuntu Cinnamon frames back in from
	# some other source tree.
	install -m 0644 "${BOOT_WORDMARK_SOURCE}" "${payload_theme_dir}/wordmark.png"
	install -m 0644 "${BOOT_LOGO_SOURCE}" "${payload_theme_dir}/logo.png"
	write_theme_file "${payload_theme_dir}/${SRC_HORSE_THEME_NAME}.plymouth" "${SRC_HORSE_THEME_NAME}"
	write_theme_script "${payload_theme_dir}/${SRC_HORSE_THEME_NAME}.script"

	install -m 0644 "${BOOT_WORDMARK_SOURCE}" "${payload_legacy_dir}/wordmark.png"
	install -m 0644 "${BOOT_LOGO_SOURCE}" "${payload_legacy_dir}/logo.png"
	write_theme_file "${payload_legacy_dir}/${LEGACY_THEME_NAME}.plymouth" "${LEGACY_THEME_NAME}"
	write_theme_script "${payload_legacy_dir}/${LEGACY_THEME_NAME}.script"

	install -m 0644 "${BOOT_WORDMARK_SOURCE}" "${payload_spinner_dir}/wordmark.png"
	install -m 0644 "${BOOT_LOGO_SOURCE}" "${payload_spinner_dir}/logo.png"
	write_theme_file "${payload_spinner_dir}/${SPINNER_THEME_NAME}.plymouth" "${SPINNER_THEME_NAME}"
	write_theme_script "${payload_spinner_dir}/${SPINNER_THEME_NAME}.script"

	install -m 0644 "${BOOT_WORDMARK_SOURCE}" "${payload_bgrt_dir}/wordmark.png"
	install -m 0644 "${BOOT_LOGO_SOURCE}" "${payload_bgrt_dir}/logo.png"
	write_theme_file "${payload_bgrt_dir}/${BGRT_THEME_NAME}.plymouth" "${BGRT_THEME_NAME}"
	write_theme_script "${payload_bgrt_dir}/${BGRT_THEME_NAME}.script"

	write_theme_file "${payload_dir}/${DEFAULT_THEME_RELATIVE_PATH}" "${SRC_HORSE_THEME_NAME}"

	install -d -m 0755 "$(dirname "${payload_dir}/${DEFAULT_ALTERNATIVE_RELATIVE_PATH}")"
	ln -snf "/usr/share/plymouth/themes/${SRC_HORSE_THEME_NAME}/${SRC_HORSE_THEME_NAME}.plymouth" \
		"${payload_dir}/${DEFAULT_ALTERNATIVE_RELATIVE_PATH}"

	install -d -m 0755 "$(dirname "${marker_path}")"
	printf 'Src Horse live initrd payload rebuilt\n' > "${marker_path}"

	(
		cd "${payload_dir}"
		find . -mindepth 1 -printf '%P\0' \
			| LC_ALL=C sort -z \
			| cpio --null -o -H newc 2>/dev/null \
			| compress_initrd_payload "${payload_compression}"
	) > "${new_payload_path}"

	cat "${prefix_path}" "${new_payload_path}" > "${new_initrd_path}"
	install -m 0644 "${new_initrd_path}" "${initrd_path}"

	rm -rf "${tmp_dir}"
}

resolve_project_iso_paths() {
	local base="$1"
	local project_root

	project_root="$(resolve_cubic_project_root "${base}")" || return 1

	find "${project_root}" -maxdepth 1 -type f -name '*.iso' | sort
}

patch_project_iso_image_if_needed() {
	local base="$1"
	local iso_path="$2"
	local project_root
	local custom_initrd_path
	local custom_md5sum_path
	local tmp_dir
	local extracted_initrd_path
	local extracted_md5sum_path
	local patched_iso_path
	local iso_checksum_path

	project_root="$(resolve_cubic_project_root "${base}")" || return 0
	custom_initrd_path="${project_root}/custom-disk/casper/initrd.gz"
	custom_md5sum_path="${project_root}/custom-disk/md5sum.txt"

	[[ -f "${iso_path}" ]] || return 0
	[[ -f "${custom_initrd_path}" ]] || return 0
	command -v xorriso >/dev/null 2>&1 || return 0

	tmp_dir="$(mktemp -d)"
	extracted_initrd_path="${tmp_dir}/casper-initrd.gz"
	extracted_md5sum_path="${tmp_dir}/md5sum.txt"
	patched_iso_path="${tmp_dir}/$(basename "${iso_path}")"

	xorriso -osirrox on -indev "${iso_path}" \
		-extract /casper/initrd.gz "${extracted_initrd_path}" \
		-extract /md5sum.txt "${extracted_md5sum_path}" \
		>/dev/null 2>&1

	if cmp -s "${extracted_initrd_path}" "${custom_initrd_path}"; then
		echo "Generated ISO already carries the Src Horse initrd: ${iso_path}" >&2
		rm -rf "${tmp_dir}"
		return 0
	fi

	update_md5sum_entry "${extracted_md5sum_path}" "./casper/initrd.gz" "${custom_initrd_path}"

	echo "Patching generated ISO initrd: ${iso_path}" >&2

	xorriso -indev "${iso_path}" -outdev "${patched_iso_path}" \
		-boot_image any replay \
		-map "${custom_initrd_path}" /casper/initrd.gz \
		-map "${extracted_md5sum_path}" /md5sum.txt \
		-commit -end \
		>/dev/null 2>&1

	mv "${patched_iso_path}" "${iso_path}"
	chmod 0644 "${iso_path}"

	iso_checksum_path="${iso_path%.iso}.md5"
	printf '%s  %s\n' "$(md5sum "${iso_path}" | awk '{print $1}')" "$(basename "${iso_path}")" > "${iso_checksum_path}"

	rm -rf "${tmp_dir}"
}

patch_project_iso_images_if_needed() {
	local base="$1"
	local project_root
	local custom_initrd_path
	local custom_md5sum_path
	local iso_path

	project_root="$(resolve_cubic_project_root "${base}")" || return 0
	custom_initrd_path="${project_root}/custom-disk/casper/initrd.gz"
	custom_md5sum_path="${project_root}/custom-disk/md5sum.txt"

	[[ -f "${custom_initrd_path}" ]] || return 0

	# Cubic regenerates the exported ISO from its own Generate step and can
	# overwrite custom-disk/casper/initrd.gz with the original Ubuntu Cinnamon
	# initrd. When an ISO already exists, patch that final artifact too.
	update_md5sum_entry "${custom_md5sum_path}" "./casper/initrd.gz" "${custom_initrd_path}"

	while IFS= read -r iso_path; do
		patch_project_iso_image_if_needed "${base}" "${iso_path}"
	done < <(resolve_project_iso_paths "${base}" || true)
}

rebuild_boot_artifacts_if_needed() {
	local base="$1"
	local live_initrd_path

	# Force the live ISO initrd when this script is pointed at a Cubic project
	# tree, including the source-disk initrd Cubic can copy back into custom-disk
	# during a rebuild, and refresh the active system initramfs when the target
	# is /.
	while IFS= read -r live_initrd_path; do
		if ! live_initrd_payload_has_src_horse_marker "${live_initrd_path}"; then
			echo "Rebuilding live initrd payload: ${live_initrd_path}" >&2
			rebuild_live_initrd_payload "${base}" "${live_initrd_path}"
		else
			echo "Live initrd already contains Src Horse marker: ${live_initrd_path}" >&2
		fi
	done < <(resolve_live_initrd_paths "${base}" || true)

	if [[ "${base}" == "/" ]] && command -v update-initramfs >/dev/null 2>&1 && [[ -d /boot ]]; then
		update-initramfs -u
	fi
}

apply_boot_assets_to_target() {
	local base="$1"

	if [[ ! -r "${BOOT_WORDMARK_SOURCE}" ]]; then
		echo "Missing boot wordmark asset: ${BOOT_WORDMARK_SOURCE}" >&2
		exit 1
	fi

	if [[ ! -r "${BOOT_LOGO_SOURCE}" ]]; then
		echo "Missing boot logo asset: ${BOOT_LOGO_SOURCE}" >&2
		exit 1
	fi

	ensure_boot_target_writable "${base}"
	install_src_horse_theme "${base}"
	rebuild_boot_artifacts_if_needed "${base}"
	patch_project_iso_images_if_needed "${base}"
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

	apply_boot_assets_to_target "${target_root}"
}

main "$@"
