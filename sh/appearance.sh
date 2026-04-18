#!/bin/bash

# Keep the desktop wallpaper asset in the repo so the installed image always
# boots into the same visual default, regardless of what Ubuntu Cinnamon ships
# in its own schema overrides.
DESKTOP_WALLPAPER_SOURCE="${SCRIPT_DIR}/assets/bg.png"
BACKGROUND_DIR=/usr/share/backgrounds/ubuntucinnamon/noble
DESKTOP_WALLPAPER_PATH="${BACKGROUND_DIR}/ubuntu_srchorse.png"
DESKTOP_WALLPAPER_URI="file://${DESKTOP_WALLPAPER_PATH}"
DESKTOP_SCHEMA_OVERRIDE=/usr/share/glib-2.0/schemas/90_srchorse-background.gschema.override

# The login screen on this machine is Slick Greeter under LightDM, and it uses
# a separate PNG background from the desktop wallpaper. Copy that exact asset
# into the image so the greeter matches the current local system.
GREETER_BACKGROUND_SOURCE="${SCRIPT_DIR}/assets/login-bg.png"
GREETER_BACKGROUND_PATH="${BACKGROUND_DIR}/ubuntu_srchorse_login.png"
LIGHTDM_DIR=/etc/lightdm
SLICK_GREETER_CONF="${LIGHTDM_DIR}/slick-greeter.conf"

if [[ ! -r "${DESKTOP_WALLPAPER_SOURCE}" ]]; then
	echo "Missing desktop wallpaper asset: ${DESKTOP_WALLPAPER_SOURCE}" >&2
	exit 1
fi

if [[ ! -r "${GREETER_BACKGROUND_SOURCE}" ]]; then
	echo "Missing greeter background asset: ${GREETER_BACKGROUND_SOURCE}" >&2
	exit 1
fi

# Install both background assets into the system backgrounds directory. Keeping
# them together makes the desktop and greeter paths stable, which matters for
# the Cinnamon schema override and the LightDM greeter configuration below.
install -d -m 0755 "${BACKGROUND_DIR}"
install -m 0644 "${DESKTOP_WALLPAPER_SOURCE}" "${DESKTOP_WALLPAPER_PATH}"
install -m 0644 "${GREETER_BACKGROUND_SOURCE}" "${GREETER_BACKGROUND_PATH}"

# Set the default Cinnamon wallpaper and solid background color. This stays in
# the schema override path because it is the most durable way to define the
# default desktop appearance for every new user created from the image.
cat <<EOF >"${DESKTOP_SCHEMA_OVERRIDE}"
[org.cinnamon.desktop.background]
color-shading-type='solid'
picture-opacity=100
picture-options='scaled'
picture-uri='${DESKTOP_WALLPAPER_URI}'
primary-color='#003181'
secondary-color='#003181'

[org.cinnamon.desktop.background.slideshow]
slideshow-enabled=false
EOF

# Mirror the local LightDM/Slick Greeter look explicitly instead of depending
# on Ubuntu Cinnamon defaults. These values reproduce the right-side login box,
# hidden action buttons, clock format, and greeter theme seen on this system.
install -d -m 0755 "${LIGHTDM_DIR}"
cat <<EOF >"${SLICK_GREETER_CONF}"
[Greeter]
background=${GREETER_BACKGROUND_PATH}
background-color=#003181
draw-user-backgrounds=false
draw-grid=false
theme-name=Yaru-cinnamon-dark
icon-theme-name=Yaru-cinnamon
font-name=Ubuntu 11
content-align=right
cursor-theme-name=default
cursor-theme-size=50
activate-numlock=true
enable-hidpi=auto
show-clock=true
clock-format=%A, %B %d %l:%M %p
show-hostname=true
show-a11y=false
show-power=false
show-keyboard=false
show-quit=true
stretch-background-across-monitors=false
only-on-monitor=auto
logo=
other-monitors-logo=
EOF

# Recompile schemas after changing the desktop override so Cinnamon picks up
# the new wallpaper defaults during first login. LightDM reads its own config
# file directly, so it does not need a separate compile step here.
glib-compile-schemas /usr/share/glib-2.0/schemas
