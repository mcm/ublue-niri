#!/usr/bin/env bash
#
# Kumori — CachyOS / Arch installer (niri + DankMaterialShell).
#
# Targets a CachyOS install where NO desktop was selected in the installer.
# Everything a graphical session needs is installed here, so nothing is
# inherited from a CachyOS desktop edition. (Installing on top of an existing
# desktop edition also works, but see the noctalia-qs guard below.)
#
# Split of responsibilities:
#   - user configs      -> $HOME/.config          (per-user, no sudo)
#   - shared assets     -> /usr/share             (sudo; the greeter runs as the
#                          `greeter` system user and cannot read $HOME, so
#                          fonts/cursors/wallpaper MUST be system-wide)
#   - packages/services -> sudo pacman / systemctl
#
# Files come from two places, with nothing duplicated between them:
#   - this directory (_cachyos/)   -> the DMS + Arch specific bits
#   - ../build_files/system_files  -> everything identical to the bootc image
#
# Usage:  ./install.sh [--skip-packages] [--skip-fonts] [--no-greeter] [--yes]

set -euo pipefail

SKIP_PACKAGES=0
SKIP_FONTS=0
WITH_GREETER=1
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-packages) SKIP_PACKAGES=1 ;;
        --skip-fonts)    SKIP_FONTS=1 ;;
        --no-greeter)    WITH_GREETER=0 ;;
        --yes|-y)        ASSUME_YES=1 ;;
        -h|--help)
            sed -n '2,25p' "$0" | sed 's|^# \{0,1\}||'
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$HERE/.." && pwd)"
SRC_SKEL="$REPO_ROOT/build_files/system_files/etc/skel"
SRC_SHARE="$REPO_ROOT/build_files/system_files/usr/share"
CFG="$HOME/.config"
STAMP="$(date +%Y%m%d-%H%M%S)"

msg()  { printf '\033[1;36m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

#############################################
## Sanity checks
#############################################

[[ -x /usr/bin/pacman ]] || die "pacman not found — this script is for CachyOS/Arch only."
[[ $EUID -ne 0 ]]        || die "Run as your normal user, not root. sudo is invoked only where needed."
[[ -d "$SRC_SKEL" ]]     || die "Cannot find $SRC_SKEL — run this from a full checkout of the repo."

# The noctalia-qs trap: noctalia's quickshell build declares
# `Provides: quickshell quickshell-git`, so `pacman -S dms-shell` finds its
# quickshell dependency already satisfied and never installs the real thing.
# DMS then runs on a much older shell: its service layer registers but its
# entire UI layer silently fails to load — a bar that draws and hovers but does
# nothing when clicked, and `dms ipc call spotlight toggle` -> "Target not
# found". Catch it up front; it costs an evening to diagnose from the symptom.
if [[ -e /usr/bin/qs ]]; then
    QS_OWNER="$(pacman -Qoq /usr/bin/qs 2>/dev/null || true)"
    if [[ -n "$QS_OWNER" && "$QS_OWNER" != "quickshell" ]]; then
        die "/usr/bin/qs is owned by '$QS_OWNER', not 'quickshell'.
    DMS will half-load against it. Remove the impostor and install the real
    quickshell before re-running:
        sudo pacman -Rdd $QS_OWNER
        sudo pacman -S quickshell"
    fi
fi

if [[ $ASSUME_YES -eq 0 ]]; then
    cat <<EOF

Installs the Kumori (Precision Overcast) niri + DankMaterialShell desktop
for user '$USER' on CachyOS/Arch.

Writes to:
  $CFG/{niri,DankMaterialShell,ghostty,gtk-3.0,gtk-4.0}
  /usr/share/{fonts,icons,backgrounds}/…$( [[ $WITH_GREETER -eq 1 ]] && printf '\n  /etc/greetd/{config,regreet}.toml + regreet.css' )

Installs packages and enables greetd/NetworkManager/bluetooth via sudo.
Existing user configs are backed up to <dir>.bak-$STAMP first.

EOF
    read -r -p "Continue? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

#############################################
## 1. Packages
#############################################

# Compositor, shell, and the apps the niri keybinds reference.
#   quickshell is named EXPLICITLY — never left to dms-shell's dependency
#   resolution, for the provides-trap reason above.
#   dgop backs DMS's system-monitor widgets.
PKGS_DESKTOP=(
    niri xwayland-satellite quickshell dms-shell dgop
    ghostty nautilus firefox
)

# Login manager: greetd + ReGreet, running under cage. NOT sddm — see
# etc/greetd/config.toml for the full reasoning. greetd waits for the greeter to
# exit before starting the session; SDDM does not, and losing that race leaves
# niri rendering into a CRTC that no longer scans out.
PKGS_GREETER=( greetd greetd-regreet cage )

# Base plumbing. A CachyOS desktop edition provides all of this; a no-desktop
# install provides none of it. --needed makes these no-ops if already present.
PKGS_BASE=(
    networkmanager
    pipewire pipewire-pulse pipewire-alsa wireplumber
    bluez bluez-utils
    polkit mate-polkit
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome
    xdg-user-dirs gnome-keyring libsecret gvfs
    power-profiles-daemon upower
    noto-fonts noto-fonts-emoji noto-fonts-cjk
    zsh
)

# Session utilities the niri config and DMS call out to.
PKGS_UTILS=(
    wl-clipboard cliphist brightnessctl ddcutil wlr-randr wlsunset playerctl
    adw-gtk-theme adwaita-cursors
)

CORE_PKGS=( "${PKGS_DESKTOP[@]}" "${PKGS_BASE[@]}" "${PKGS_UTILS[@]}" )
[[ $WITH_GREETER -eq 1 ]] && CORE_PKGS+=( "${PKGS_GREETER[@]}" )

# dms-shell and dgop may not be in every CachyOS repo generation.
MAYBE_AUR_PKGS=( dms-shell dgop )

aur_helper() {
    for h in paru yay; do
        command -v "$h" >/dev/null 2>&1 && { echo "$h"; return 0; }
    done
    return 1
}

if [[ $SKIP_PACKAGES -eq 1 ]]; then
    msg "Skipping package installation (--skip-packages)."
else
    # Check names before handing the list to pacman, so one renamed package
    # gives a clear message instead of a bulk depsolve failure. Most likely to
    # drift: adw-gtk-theme and adwaita-cursors (named adw-gtk3-theme /
    # adwaita-cursor-theme on Fedora).
    msg "Checking package names against your repos…"
    missing=()
    for pkg in "${CORE_PKGS[@]}"; do
        pacman -Si "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    # Anything in the maybe-AUR set is handled separately below, not an error.
    filtered_missing=()
    for m in "${missing[@]}"; do
        skip=0
        for a in "${MAYBE_AUR_PKGS[@]}"; do [[ "$m" == "$a" ]] && skip=1; done
        [[ $skip -eq 0 ]] && filtered_missing+=("$m")
    done

    if [[ ${#filtered_missing[@]} -gt 0 ]]; then
        warn "not found in your configured repos: ${filtered_missing[*]}"
        warn "Search for the current name with:  pacman -Ss <name>"
        if [[ $ASSUME_YES -eq 0 ]]; then
            read -r -p "Install the rest anyway? [y/N] " reply
            [[ "$reply" =~ ^[Yy]$ ]] || die "Aborted. Fix the names and re-run."
        fi
    fi

    # Drop every unresolvable name (including maybe-AUR ones) from the bulk run.
    install_now=()
    for pkg in "${CORE_PKGS[@]}"; do
        skip=0
        for m in "${missing[@]}"; do [[ "$pkg" == "$m" ]] && skip=1; done
        [[ $skip -eq 0 ]] && install_now+=("$pkg")
    done

    msg "Installing ${#install_now[@]} packages…"
    # --asexplicit so these are never swept up as orphans by a later -Rs.
    # Plain `-S --needed` does NOT re-mark an already-installed dependency.
    sudo pacman -S --needed --asexplicit "${install_now[@]}"

    for pkg in "${MAYBE_AUR_PKGS[@]}"; do
        pacman -Qq "$pkg" >/dev/null 2>&1 && continue
        if pacman -Si "$pkg" >/dev/null 2>&1; then
            sudo pacman -S --needed --asexplicit "$pkg"
        elif helper="$(aur_helper)"; then
            msg "$pkg not in the repos; installing from the AUR with $helper…"
            "$helper" -S --needed "$pkg"
        else
            warn "$pkg missing and no AUR helper (paru/yay) found — install it manually."
            warn "  https://danklinux.com/docs/dankmaterialshell/installation"
        fi
    done
fi

#############################################
## 2. Services
#############################################
# A no-desktop CachyOS install enables NetworkManager and sshd but nothing
# graphical. Everything here is idempotent.

if [[ $SKIP_PACKAGES -eq 0 ]]; then
    msg "Enabling services…"
    sudo systemctl enable NetworkManager.service
    sudo systemctl enable bluetooth.service

    if [[ $WITH_GREETER -eq 1 ]]; then
        # sddm and greetd both claim the display-manager.service alias, and
        # systemd refuses to enable the second one while the first owns the
        # symlink. sddm MUST be disabled before greetd is enabled — and two
        # login managers racing for VT 1 is a worse outcome than either alone.
        if systemctl is-enabled sddm.service >/dev/null 2>&1; then
            warn "sddm.service is enabled and conflicts with greetd — disabling it."
            sudo systemctl disable sddm.service
        fi
        # `systemctl disable` clears the alias it created, but not one written by
        # hand (the bootc image does exactly that with ln -sf).
        if [[ -L /etc/systemd/system/display-manager.service ]] &&
           [[ "$(readlink -f /etc/systemd/system/display-manager.service)" == *sddm* ]]; then
            warn "removing stale display-manager.service symlink pointing at sddm"
            sudo rm -f /etc/systemd/system/display-manager.service
        fi
        sudo systemctl enable greetd.service
    fi
    # pipewire/wireplumber are socket-activated per-user; no system enable.
fi

#############################################
## 3. Shared assets  ->  /usr/share
#############################################
# These MUST be system-wide, not in ~/.local/share: the greeter runs as the
# `greeter` user and cannot read your home directory. With no system fonts it
# falls back to a default sans; with no system cursor theme it draws the default
# arrow; with no system wallpaper it renders a flat background. All three look
# like "the theme didn't apply".

if [[ $SKIP_FONTS -eq 1 ]]; then
    msg "Skipping fonts (--skip-fonts)."
else
    msg "Installing brand fonts to /usr/share/fonts/kumori…"
    tmpfonts="$(mktemp -d)"
    curl -fL --retry 3 -o "$tmpfonts/GeistMono.ttf" \
        "https://github.com/google/fonts/raw/main/ofl/geistmono/GeistMono%5Bwght%5D.ttf"
    curl -fL --retry 3 -o "$tmpfonts/Geist.ttf" \
        "https://github.com/google/fonts/raw/main/ofl/geist/Geist%5Bwght%5D.ttf"
    curl -fL --retry 3 -o "$tmpfonts/SchibstedGrotesk.ttf" \
        "https://github.com/google/fonts/raw/main/ofl/schibstedgrotesk/SchibstedGrotesk%5Bwght%5D.ttf"
    sudo install -d -m755 /usr/share/fonts/kumori
    sudo install -m644 "$tmpfonts"/*.ttf /usr/share/fonts/kumori/
    rm -rf "$tmpfonts"
    sudo fc-cache -f >/dev/null
fi

msg "Installing the Simp1e Precision Overcast cursor theme to /usr/share/icons…"
sudo rm -rf /usr/share/icons/Simp1e-Precision-Overcast
sudo cp -R "$SRC_SHARE/icons/Simp1e-Precision-Overcast" /usr/share/icons/

msg "Installing the wallpaper to /usr/share/backgrounds/kumori…"
sudo install -d -m755 /usr/share/backgrounds/kumori
sudo install -m644 "$SRC_SHARE/backgrounds/kumori/kumori.jpg" /usr/share/backgrounds/kumori/

#############################################
## 4. User configs  ->  ~/.config
#############################################

backup() {
    [[ -e "$1" ]] || return 0
    mv "$1" "$1.bak-$STAMP"
    warn "backed up $(basename "$1") -> $(basename "$1").bak-$STAMP"
}

mkdir -p "$CFG"

msg "Installing niri config…"
backup "$CFG/niri"
mkdir -p "$CFG/niri/cfg"
install -m644 "$SRC_SKEL/.config/niri/config.kdl" "$CFG/niri/config.kdl"
# Identical to the bootc image.
for f in animation.kdl display.kdl input.kdl layout.kdl; do
    install -m644 "$SRC_SKEL/.config/niri/cfg/$f" "$CFG/niri/cfg/$f"
done
# DMS + Arch specific: dms autostart, dms ipc keybinds, matugen kill-switch,
# quickshell layer rule, Arch polkit path.
for f in autostart.kdl keybinds.kdl misc.kdl rules.kdl; do
    install -m644 "$HERE/skel/.config/niri/cfg/$f" "$CFG/niri/cfg/$f"
done

msg "Installing ghostty + GTK theming…"
for d in ghostty gtk-3.0 gtk-4.0; do
    backup "$CFG/$d"
    mkdir -p "$CFG/$d"
    cp -R "$SRC_SKEL/.config/$d/." "$CFG/$d/"
done

# DMS owns settings.json at runtime (bar layout, widget state, …), so merge our
# two theme keys into an existing file rather than clobbering it.
msg "Installing DankMaterialShell theme…"
DMSDIR="$CFG/DankMaterialShell"
mkdir -p "$DMSDIR"
install -m644 "$HERE/skel/.config/DankMaterialShell/precision-overcast.json" \
    "$DMSDIR/precision-overcast.json"
THEME_PATH="$DMSDIR/precision-overcast.json"

if [[ -f "$DMSDIR/settings.json" ]] && command -v jq >/dev/null 2>&1; then
    tmp="$(mktemp)"
    jq --arg p "$THEME_PATH" \
       '.currentThemeName = "custom" | .customThemeFile = $p' \
       "$DMSDIR/settings.json" > "$tmp" && mv "$tmp" "$DMSDIR/settings.json"
    msg "merged theme keys into your existing DMS settings.json"
else
    [[ -f "$DMSDIR/settings.json" ]] && {
        backup "$DMSDIR/settings.json"
        warn "jq not installed — wrote a fresh settings.json; old one backed up."
    }
    sed "s|__HOME__|$HOME|g" \
        "$HERE/skel/.config/DankMaterialShell/settings.json" > "$DMSDIR/settings.json"
fi

#############################################
## 5. SDDM greeter
#############################################

if [[ $WITH_GREETER -eq 1 ]]; then
    msg "Installing the Precision Overcast greeter (greetd + ReGreet)…"
    sudo install -d -m755 /etc/greetd
    sudo install -m644 "$HERE/etc/greetd/config.toml"  /etc/greetd/config.toml
    sudo install -m644 "$HERE/etc/greetd/regreet.toml" /etc/greetd/regreet.toml
    sudo install -m644 "$HERE/etc/greetd/regreet.css"  /etc/greetd/regreet.css

    # ReGreet caches last-user/last-session as the `greeter` user.
    sudo install -d -o greeter -g greeter -m755 /var/cache/regreet 2>/dev/null || true

    # (sddm is disabled and greetd enabled back in the Services section — the
    # display-manager.service alias forces that ordering.)

    if [[ ! -f /usr/share/doc/greetd-regreet/regreet.sample.toml ]]; then
        warn "regreet.sample.toml not found; can't verify our regreet.toml keys."
    fi
fi

#############################################
## 6. Appearance defaults
#############################################
# The bootc image ships these as a system dconf db. Per-user here — same effect,
# no sudo. Under niri there is no GNOME settings daemon, so without this
# libadwaita apps render light and the gtk.css recolor looks inconsistent.

if command -v gsettings >/dev/null 2>&1; then
    msg "Setting GTK appearance defaults…"
    gset() {
        gsettings set org.gnome.desktop.interface "$1" "$2" 2>/dev/null \
            || warn "could not set $1 (schema missing?)"
    }
    gset color-scheme 'prefer-dark'
    gset gtk-theme 'adw-gtk3-dark'
    gset cursor-theme 'Simp1e-Precision-Overcast'
    gset font-name 'Schibsted Grotesk 10'
    gset monospace-font-name 'Geist Mono 11'
    gset accent-color 'slate'
else
    warn "gsettings not found — GTK4/libadwaita apps may render light."
fi

#############################################
## Done
#############################################

cat <<EOF

$(msg "Done.")

Next steps:
  1. Reboot (or: sudo systemctl start greetd) and log in to the niri session.
  2. Set the wallpaper once — DMS has no wallpaper-directory setting:
       dms ipc call wallpaper set /usr/share/backgrounds/kumori/kumori.jpg
  3. Set the shell fonts in DMS: Settings -> Appearance, "Schibsted Grotesk"
     (UI) and "Geist Mono" (fixed). Not scripted — the settings.json key names
     for fonts are undocumented and guessing at them corrupts the file.

Notes:
  - Static theming depends on DMS_DISABLE_MATUGEN=1, set in niri's environment
    block (cfg/misc.kdl). Without it DMS regenerates its palette from the
    wallpaper and overwrites Precision Overcast.
  - If DMS's "Application Theming" is on it may overwrite ~/.config/gtk-3.0/gtk.css.
  - Backups from this run are suffixed .bak-$STAMP
  - If a login ever comes up to a frozen screen, recover with a modeset kick
    rather than restarting the login manager:
       niri msg output eDP-1 off && niri msg output eDP-1 on

EOF
