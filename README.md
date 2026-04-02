# Ubuntu SrcHorse

Ubuntu SrcHorse is a custom Ubuntu image build that turns a stock Ubuntu 24.04 Noble base into a branded Cinnamon workstation with a preloaded development stack, local services, desktop defaults, and first-boot seeding for the pieces Cubic cannot install cleanly inside its chroot-like environment.

This repo is optimized for use inside Cubic, but the same installer can also be run directly on a fresh Ubuntu 24.04 machine.

## Get The Repo

```bash
git clone https://github.com/srchorse/os /opt/os-github
cd /opt/os-github
```

## Supported Base

- Target release: Ubuntu 24.04 LTS (Noble)
- Primary workflow: Ubuntu Cinnamon 24.04 rootfs inside Cubic
- Expected environment for image building: Cubic chroot
- Not the target: Ubuntu 25.10 package sets and PPAs

The scripts are tuned around the package names, branding, panel assets, and boot paths used by the Noble Ubuntu Cinnamon build. Running the installer on a different Ubuntu flavor can still install most of the software, but the Cinnamon-specific appearance and cleanup steps are written for this base.

## What This OS Contains

### Branding and desktop defaults

- Rebrands the system to `Ubuntu Src Horse` in release metadata, console banners, GRUB-visible branding, and related ISO text assets
- Replaces the Plymouth spinner/theme payload with the repo boot assets under `assets/boot/`
- Applies a custom desktop wallpaper from `assets/bg.png`
- Applies a custom LightDM Slick Greeter background from `assets/login-bg.png`
- Seeds Cinnamon panel and menu defaults from `assets/panel/`
- Installs dconf defaults for the panel layout and related Cinnamon behavior

### Network and system defaults

- Installs `ufw` and `gufw`
- Sets firewall defaults to deny unsolicited inbound traffic and allow normal outbound traffic
- Enables `ufw` at boot without forcing live firewall startup inside Cubic
- Creates the runtime directories and service-policy guards needed for package installation in Cubic

### Development workstation stack

- Git tooling: `git`, `git-lfs`
- Basic shell/build tools: `curl`, `wget`, `jq`, `cmake`, `zip`, `unzip`, `7zip`, `nano`
- Browsers and editors: `google-chrome-stable`, `sublime-text`, `zoom`
- Desktop utilities: `guake`, `redshift`, `redshift-gtk`, `caffeine`, `transmission`, `file-roller`, `gnome-disk-utility`, `simplescreenrecorder`, `vlc`
- Creative tools: `gimp`, `inkscape`, `libreoffice-common`
- Virtualization and imaging tools: `qemu-system-x86`, `qemu-system`, `qemu-utils`, `virtualbox`, `grub2-common`, `rsync`

### Local services and backend stack

- Web server: `apache2`
- PHP runtime: `php8.4`, `php8.4-fpm`, and a broad set of extensions
- PHP integration: Apache is configured for PHP-FPM with `proxy_fcgi` and `setenvif`
- Data/cache services: `memcached`, `postgresql`, `redis`, `redis-server`
- Package and framework tooling: Composer, Symfony CLI, and global Drush

### Language and CLI tooling

- JavaScript: `nodejs`, `npm`, then `n latest` and `npm@latest`
- Global npm tools: `@openai/codex`, `@google/gemini-cli`, `@github/copilot`, `@githubnext/github-copilot-cli`, `electron`, `heroku`, `nodemon`, `yo`
- Python: `python3`, `python3-pip`
- Go: `golang`
- Java build tools: `gradle`, `maven`
- Ruby: `ruby-full`, `rake`
- Rust bootstrap: `rustup`
- Other CLI tools: `gh`, `acli`, `eslint`, `perl`

### Third-party apt repositories added by the build

- Ondrej PHP PPA
- Atlassian CLI apt repository
- Sublime Text apt repository
- Google Chrome apt repository
- GitHub CLI apt repository

## PHP Modules Installed

The PHP build installs `php8.4` plus these extension packages:

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

## First-Boot Behavior

Some components are intentionally deferred until the installed machine boots normally, because Cubic does not provide a live init system or working `snapd` socket during the build.

On first real boot, the image can automatically:

- Install `mysql-client` and `mysql-server`
- Install snaps:
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
- Remove seeded snaps that SrcHorse does not keep:
  - `firefox`
  - `thunderbird`

Done markers are stored under `/var/lib/os-sh/`, and logs are written to:

- `/var/log/install-firstboot-snaps.log`
- `/var/log/install-firstboot-mysql.log`
- `/var/log/purge-firstboot-snaps.log`

## What Gets Removed From the Stock Ubuntu Cinnamon Image

The build purges a large chunk of the default desktop bundle so the final image starts closer to the SrcHorse target setup. That includes:

- Firefox and Thunderbird
- Pidgin and HexChat
- Rhythmbox and Totem
- Gedit and Alacritty
- Cheese and Brasero
- The stock GNOME games bundle

The full purge list lives in [`sh/purge.sh`](/home/t/www/os-github/sh/purge.sh).

## Repo Layout

The authoritative install flow is shell-first and split by concern:

- [`os.sh`](/home/t/www/os-github/os.sh): root entrypoint; sources the installer parts in order and applies branding/boot steps last
- [`local.sh`](/home/t/www/os-github/local.sh): host-side helper for applying only release/boot branding to an unpacked target rootfs
- [`sh/setup.sh`](/home/t/www/os-github/sh/setup.sh): Cubic-safe environment prep and runtime directory creation
- [`sh/base.sh`](/home/t/www/os-github/sh/base.sh): base apt tools
- [`sh/repo.sh`](/home/t/www/os-github/sh/repo.sh): third-party apt repository setup
- [`sh/core.sh`](/home/t/www/os-github/sh/core.sh): main desktop, tooling, and application packages
- [`sh/firewall.sh`](/home/t/www/os-github/sh/firewall.sh): `ufw` and `gufw` defaults
- [`sh/php.sh`](/home/t/www/os-github/sh/php.sh): PHP 8.4 stack, Composer, Symfony CLI, Drush
- [`sh/mysql.sh`](/home/t/www/os-github/sh/mysql.sh): first-boot MySQL installer service
- [`sh/snap.sh`](/home/t/www/os-github/sh/snap.sh): first-boot snap installer service
- [`sh/npm.sh`](/home/t/www/os-github/sh/npm.sh): Node/npm upgrades and global npm packages
- [`sh/purge.sh`](/home/t/www/os-github/sh/purge.sh): package removals and first-boot snap cleanup
- [`sh/panel.sh`](/home/t/www/os-github/sh/panel.sh): Cinnamon panel/menu defaults and desktop overrides
- [`sh/appearance.sh`](/home/t/www/os-github/sh/appearance.sh): wallpaper and greeter defaults
- [`sh/release.sh`](/home/t/www/os-github/sh/release.sh): release metadata and visible branding rewrite
- [`sh/boot.sh`](/home/t/www/os-github/sh/boot.sh): Plymouth theme replacement, live initrd patching, ISO patching

## How To Use It With Cubic

### 1. Start from the right base

Use a Cubic project built from a Noble Ubuntu Cinnamon image. This repo is written around that package set and branding layout.

### 2. Put the repo inside the Cubic environment

Inside Cubic, the working copy is typically under `/root/os-github`.

### 3. Run the installer inside Cubic

From the Cubic terminal:

```bash
cd /root/os-github
sudo bash ./os.sh
```

What this does in Cubic:

- Prepares the Cubic chroot for non-interactive apt installs
- Adds the required apt repositories
- Installs the desktop, development, and service packages
- Seeds the Cinnamon defaults and appearance assets
- Rebrands the image to `Ubuntu Src Horse`
- Replaces the Plymouth theme and patches the live initrd payload used by the ISO

What it does not do in Cubic:

- It does not install snaps during the build
- It does not install MySQL packages during the build

Those pieces are deferred to first boot on the installed machine.

### 4. Finish the image in Cubic

After the installer completes:

- Continue with Cubic's normal generate/export flow
- Boot the resulting ISO or installed system normally
- Let the first-boot services finish seeding snaps and MySQL

## How To Run It Manually On a Fresh Ubuntu Machine

### Supported manual target

Use a fresh Ubuntu 24.04 machine. The closest match is a fresh Ubuntu Cinnamon 24.04 install, because the panel, branding, and purge logic are written for that environment.

### 1. Run the installer as root

```bash
sudo bash ./os.sh
```

This applies the same package, desktop, branding, firewall, and tooling setup directly to the running machine.

### 2. Reboot

Reboot after the script finishes so the first-boot services can run on a normal systemd-based boot:

```bash
sudo reboot
```

After reboot, the machine can finish:

- snap installation
- MySQL installation
- seeded Firefox/Thunderbird snap removal

### 3. Verify the deferred jobs if needed

Check:

- `/var/log/install-firstboot-snaps.log`
- `/var/log/install-firstboot-mysql.log`
- `/var/log/purge-firstboot-snaps.log`

## Host-Side Branding For an Unpacked Rootfs

If you already have an unpacked target rootfs and only want to reapply the release and boot branding, use [`local.sh`](/home/t/www/os-github/local.sh) instead of the full installer.

Example against a restored Cubic `custom-root` tree:

```bash
sudo bash ./local.sh ~/www/os/custom-root
```

`local.sh` does not install the package stack. It only reapplies:

- release metadata branding
- visible disk-tree branding rewrites
- Plymouth theme assets
- live initrd and ISO boot branding fixes when the target is a Cubic project tree

## Notes

- `local.sh` is the host-side branding/boot repair helper
- The package lists in `sh/*.sh` are the source of truth if this README ever drifts
