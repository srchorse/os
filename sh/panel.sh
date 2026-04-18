#!/bin/bash

# These assets were captured from the current Cinnamon desktop so the panel can
# be reapplied without hardcoding every JSON blob directly into the script.
# Keeping them under assets/ also makes the saved state easy to inspect later.
PANEL_ASSET_DIR="${SCRIPT_DIR}/assets/panel"
PANEL_DCONF_ASSET="${PANEL_ASSET_DIR}/dconf/cinnamon-panel.dconf"
PANEL_SKEL_ASSET="${PANEL_ASSET_DIR}/skel"
PANEL_MENU_LOCAL_DESKTOPS_ASSET="${PANEL_ASSET_DIR}/menu/local-menu-desktop-files.txt"
PANEL_SYSTEM_APPLICATIONS_DIR="/usr/local/share/applications"
PANEL_SYSTEM_DESKTOP_DIRECTORIES_DIR="/usr/local/share/desktop-directories"
PANEL_SYSTEM_ICONS_DIR="/usr/local/share/icons"
PANEL_HIDDEN_DESKTOPS=(
	simple-scan.desktop
	org.gnome.FileRoller.desktop
	groovyConsole.desktop
	qemu.desktop
	org.gnome.Screenshot.desktop
)

install_hidden_menu_override() {
	local desktop_file="$1"
	local target_path="${PANEL_SYSTEM_APPLICATIONS_DIR}/${desktop_file}"
	local source_path=""
	local tmp_file

	if [[ -f "${target_path}" ]]; then
		source_path="${target_path}"
	elif [[ -f "/usr/share/applications/${desktop_file}" ]]; then
		source_path="/usr/share/applications/${desktop_file}"
	fi

	if [[ -n "${source_path}" && "${source_path}" != "${target_path}" ]]; then
		install -m 0644 "${source_path}" "${target_path}"
	elif [[ -z "${source_path}" ]]; then
		cat <<EOF >"${target_path}"
[Desktop Entry]
Type=Application
Name=${desktop_file}
EOF
	fi

	tmp_file="$(mktemp)"

	awk '
		BEGIN {
			in_entry = 0
			inserted = 0
		}
		/^\[Desktop Entry\]$/ {
			in_entry = 1
			print
			next
		}
		/^\[/ && in_entry {
			if (!inserted) {
				print "NoDisplay=true"
				inserted = 1
			}
			in_entry = 0
		}
		in_entry && /^NoDisplay=/ {
			if (!inserted) {
				print "NoDisplay=true"
				inserted = 1
			}
			next
		}
		{
			print
		}
		END {
			if (in_entry && !inserted) {
				print "NoDisplay=true"
			}
		}
	' "${target_path}" > "${tmp_file}"

	install -m 0644 "${tmp_file}" "${target_path}"
	rm -f "${tmp_file}"
}

rewrite_cinnamon_menu_paths() {
	local menu_file="$1"

	[[ -f "${menu_file}" ]] || return 0

	sed -E -i \
		-e "s|/home/[^/]+/.local/share/applications|${PANEL_SYSTEM_APPLICATIONS_DIR}|g" \
		-e "s|/home/[^/]+/.local/share/desktop-directories|${PANEL_SYSTEM_DESKTOP_DIRECTORIES_DIR}|g" \
		"${menu_file}"
}

seed_panel_home_state() {
	local home_dir="$1"
	local owner_group="$2"

	install -d -m 0755 "${home_dir}/.config/cinnamon"
	install -d -m 0755 "${home_dir}/.config/menus"

	if [[ -d "${PANEL_SKEL_ASSET}/.config/cinnamon" ]]; then
		cp -a "${PANEL_SKEL_ASSET}/.config/cinnamon/." "${home_dir}/.config/cinnamon/"
	fi

	if [[ -d "${PANEL_SKEL_ASSET}/.config/menus" ]]; then
		cp -a "${PANEL_SKEL_ASSET}/.config/menus/." "${home_dir}/.config/menus/"
		rewrite_cinnamon_menu_paths "${home_dir}/.config/menus/cinnamon-applications.menu"
	fi

	if [[ -n "${owner_group}" ]]; then
		chown -R "${owner_group}" "${home_dir}/.config/cinnamon" "${home_dir}/.config/menus"
	fi
}

if [[ ! -r "${PANEL_DCONF_ASSET}" ]]; then
	echo "Missing panel dconf asset: ${PANEL_DCONF_ASSET}" >&2
	exit 1
fi

if [[ ! -d "${PANEL_SKEL_ASSET}/.config/cinnamon/spices" ]]; then
	echo "Missing panel applet asset directory: ${PANEL_SKEL_ASSET}/.config/cinnamon/spices" >&2
	exit 1
fi

if [[ ! -r "${PANEL_MENU_LOCAL_DESKTOPS_ASSET}" ]]; then
	echo "Missing panel menu asset list: ${PANEL_MENU_LOCAL_DESKTOPS_ASSET}" >&2
	exit 1
fi

# Cinnamon splits the panel between applet JSON in ~/.config/cinnamon/spices
# and the menu applet definition in ~/.config/menus. Seed both into /etc/skel
# for future users and into any existing /home/* tree already present in the
# image, because live-session users never inherit /etc/skel on first boot.
seed_panel_home_state /etc/skel "0:0"

shopt -s nullglob
for home_dir in /home/*; do
	[[ -d "${home_dir}" ]] || continue
	[[ "$(basename "${home_dir}")" == "lost+found" ]] && continue

	seed_panel_home_state "${home_dir}" "$(stat -c '%u:%g' "${home_dir}")"
done
shopt -u nullglob

# The live menu uses a small set of local desktop overrides, category metadata,
# and bundled icons for Chrome apps plus a few third-party launchers. Install
# those system-wide under /usr/local/share so the menu renders consistently.
install -d -m 0755 "${PANEL_SYSTEM_APPLICATIONS_DIR}"
install -d -m 0755 "${PANEL_SYSTEM_DESKTOP_DIRECTORIES_DIR}"
install -d -m 0755 "${PANEL_SYSTEM_ICONS_DIR}"

if [[ -d "${PANEL_SKEL_ASSET}/.local/share/desktop-directories" ]]; then
	cp -a "${PANEL_SKEL_ASSET}/.local/share/desktop-directories/." "${PANEL_SYSTEM_DESKTOP_DIRECTORIES_DIR}/"
fi

while IFS= read -r desktop_file; do
	[[ -z "${desktop_file}" || "${desktop_file}" =~ ^# ]] && continue

	source_path="${PANEL_SKEL_ASSET}/.local/share/applications/${desktop_file}"

	if [[ ! -f "${source_path}" ]]; then
		echo "Missing panel menu desktop asset: ${source_path}" >&2
		exit 1
	fi

	install -m 0644 "${source_path}" "${PANEL_SYSTEM_APPLICATIONS_DIR}/${desktop_file}"
done < "${PANEL_MENU_LOCAL_DESKTOPS_ASSET}"

if [[ -d "${PANEL_SKEL_ASSET}/.local/share/icons" ]]; then
	cp -a "${PANEL_SKEL_ASSET}/.local/share/icons/." "${PANEL_SYSTEM_ICONS_DIR}/"
fi

# Hide a few stock launchers from the Cinnamon menu without uninstalling the
# underlying packages. Using same-name desktop overrides keeps the menu trim
# while leaving the applications available for direct invocation if needed.
for desktop_file in "${PANEL_HIDDEN_DESKTOPS[@]}"; do
	install_hidden_menu_override "${desktop_file}"
done

if command -v update-desktop-database >/dev/null 2>&1; then
	update-desktop-database "${PANEL_SYSTEM_APPLICATIONS_DIR}" || true
fi

if [[ -d "${PANEL_SYSTEM_ICONS_DIR}/hicolor" ]] && command -v gtk-update-icon-cache >/dev/null 2>&1; then
	gtk-update-icon-cache -q -t -f "${PANEL_SYSTEM_ICONS_DIR}/hicolor" || true
fi

# The dconf defaults cover the top-level panel structure, enabled applets, and
# workspace count. Individual applet behavior, including the workspace switcher,
# lives in the seeded spices JSON above.
# Ensure the local dconf database is active, then install the captured dump.
install -d -m 0755 /etc/dconf/profile
install -d -m 0755 /etc/dconf/db/local.d

if [[ -f /etc/dconf/profile/user ]]; then
	grep -qxF 'user-db:user' /etc/dconf/profile/user || printf '%s\n' 'user-db:user' >>/etc/dconf/profile/user
	grep -qxF 'system-db:local' /etc/dconf/profile/user || printf '%s\n' 'system-db:local' >>/etc/dconf/profile/user
else
	cat <<'EOF' >/etc/dconf/profile/user
user-db:user
system-db:local
EOF
fi

install -m 0644 "${PANEL_DCONF_ASSET}" /etc/dconf/db/local.d/40-srchorse-panel
dconf update
