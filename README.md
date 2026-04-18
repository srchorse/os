# Ubuntu SrcHorse

Ubuntu SrcHorse is a shell-based Ubuntu 24.04 workstation upgrader. Run it on an existing Ubuntu install to add the SrcHorse package set, developer tooling, local services, selected desktop defaults, and cleanup of stock applications you do not want to keep.

The intended use is a normal, already-booted Ubuntu machine.

## Supported Target

- Ubuntu 24.04 LTS (Noble)
- Best fit: Ubuntu Cinnamon 24.04
- Also reasonable: other Ubuntu 24.04 desktop installs, as long as you are okay with Cinnamon-oriented defaults and package cleanup
- Not the target: Ubuntu 25.10 or other non-24.04 package sets

## What The Installer Does

### Adds third-party apt repositories

- Ondrej PHP PPA
- Atlassian CLI apt repository
- Sublime Text apt repository
- Google Chrome apt repository
- GitHub CLI apt repository

### Installs the main workstation stack

- Git tooling: `git`, `git-lfs`
- Shell and build tools: `curl`, `wget`, `jq`, `cmake`, `zip`, `gzip`, `unzip`, `7zip`, `nano`
- Browsers and editors: `google-chrome-stable`, `sublime-text`, `zoom`
- Desktop utilities: `guake`, `redshift`, `redshift-gtk`, `caffeine`, `transmission`, `file-roller`, `gnome-disk-utility`, `simplescreenrecorder`, `vlc`
- Creative tools: `gimp`, `inkscape`, `libreoffice-common`
- Virtualization and imaging tools: `qemu-system-x86`, `qemu-system`, `qemu-utils`, `virtualbox`, `grub2-common`, `rsync`
- Containers and services: `docker.io`, `docker-compose-v2`, `apache2`, `memcached`, `postgresql`, `redis`, `redis-server`
- Language tooling: `nodejs`, `npm`, `python3`, `python3-pip`, `golang`, `gradle`, `maven`, `ruby-full`, `rake`, `rustup`, `perl`
- CLI tools: `gh`, `acli`, `eslint`

### Installs PHP and backend tooling

- `php8.4`
- `php8.4-fpm`
- Apache PHP-FPM integration with `proxy_fcgi` and `setenvif`
- Composer
- Symfony CLI
- Global Drush

### Installs snaps immediately

- `discord`
- `plex-desktop`
- `slack`
- `spotify`
- `teams-for-linux`
- `mc-installer`
- `snap-store`
- `trello-cli`
- `canonical-livepatch`
- `flutter --classic`
- `blender --classic`

If one of those snaps is already installed, the installer refreshes it instead of reinstalling it.

### Configures system defaults

- Installs and enables `ufw` and `gufw`
- Sets `ufw` defaults to deny unsolicited inbound traffic and allow normal outbound traffic
- Creates the runtime directories Apache and apt keyring setup expect before the heavier package installs run

### Applies desktop defaults

- Seeds Cinnamon panel and menu defaults from [`assets/panel/`](/home/t/www/os-github/assets/panel)
- Applies a desktop wallpaper from [`assets/bg.png`](/home/t/www/os-github/assets/bg.png)
- Applies a Slick Greeter background from [`assets/login-bg.png`](/home/t/www/os-github/assets/login-bg.png)

### Removes stock packages you do not want to keep

- Firefox and Thunderbird
- Pidgin and HexChat
- Rhythmbox and Totem
- Gedit and Alacritty
- Cheese and Brasero
- The stock GNOME games bundle

The package cleanup lives in [`sh/purge.sh`](/home/t/www/os-github/sh/purge.sh).

## PHP Modules Installed

The PHP step installs `php8.4` plus these extension packages:

- `apcu`
- `ast`
- `bcmath`
- `bz2`
- `cli`
- `common`
- `curl`
- `decimal`
- `dev`
- `fpm`
- `gd`
- `grpc`
- `http`
- `igbinary`
- `imap`
- `intl`
- `mbstring`
- `memcached`
- `mysql`
- `oauth`
- `opcache`
- `pgsql`
- `protobuf`
- `ps`
- `pspell`
- `psr`
- `readline`
- `redis`
- `smbclient`
- `soap`
- `solr`
- `sqlite3`
- `ssh2`
- `tidy`
- `uploadprogress`
- `uuid`
- `xdebug`
- `xlswriter`
- `xml`
- `xmlrpc`
- `xsl`
- `yaml`
- `zip`

## Repo Layout

The install flow is split into small repo-local shell parts:

- [`os.sh`](/home/t/www/os-github/os.sh): root entrypoint; sources the installer parts in order
- [`sh/setup.sh`](/home/t/www/os-github/sh/setup.sh): non-interactive install environment and shared runtime preparation
- [`sh/base.sh`](/home/t/www/os-github/sh/base.sh): base apt tools
- [`sh/repo.sh`](/home/t/www/os-github/sh/repo.sh): third-party apt repository setup
- [`sh/core.sh`](/home/t/www/os-github/sh/core.sh): main desktop, tooling, and application packages
- [`sh/firewall.sh`](/home/t/www/os-github/sh/firewall.sh): `ufw` and `gufw` defaults
- [`sh/php.sh`](/home/t/www/os-github/sh/php.sh): PHP 8.4 stack, Composer, Symfony CLI, Drush
- [`sh/mysql.sh`](/home/t/www/os-github/sh/mysql.sh): immediate MySQL package installation
- [`sh/snap.sh`](/home/t/www/os-github/sh/snap.sh): immediate snap installation and refresh
- [`sh/npm.sh`](/home/t/www/os-github/sh/npm.sh): Node/npm upgrades and global npm packages
- [`sh/purge.sh`](/home/t/www/os-github/sh/purge.sh): package removals and snap cleanup
- [`sh/panel.sh`](/home/t/www/os-github/sh/panel.sh): Cinnamon panel/menu defaults and desktop overrides
- [`sh/appearance.sh`](/home/t/www/os-github/sh/appearance.sh): wallpaper and greeter defaults

## How To Run It

### 1. Clone the repo

```bash
git clone https://github.com/srchorse/os /opt/os-github
cd /opt/os-github
```

### 2. Run the installer as root

```bash
sudo bash ./os.sh
```

### 3. Reboot when it finishes

The script installs packages and snaps directly on the running machine, but a reboot is still the cleanest way to pick up service startup, shell path changes, desktop defaults, and any package-triggered session updates.

```bash
sudo reboot
```

## What To Expect

- The script uses `apt-get` non-interactively
- Apache, PHP-FPM, MySQL, Redis, PostgreSQL, Docker, and snapd may start or restart during the run
- Existing snaps in the managed list may be refreshed to their latest available channel revision
- Firefox and Thunderbird are removed both as packages and, when present, as snaps
- Cinnamon defaults are reseeded system-wide for future users and any current `/home/*` users found during the run

## Notes

- This is written for a normal Ubuntu system
- If you only want a subset of the behavior, adjust the sourced parts in [`os.sh`](/home/t/www/os-github/os.sh) before running it
