#!/usr/bin/env bash
#
# Kumori — CachyOS / Arch installer (niri + DankMaterialShell).
#
# Installs the Precision Overcast desktop for the *invoking user*. Unlike the
# bootc image (which bakes everything into /etc/skel at build time), this is a
# per-user install: everything lands under $HOME, and only `pacman` needs sudo.
#
# Files come from two places:
#   - this directory (_cachyos/skel)  -> the DMS/Arch-specific bits
#   - ../build_files/system_files     -> everything that is identical to the
#                                        Fedora image (ghostty, GTK, cursor
#                                        theme, wallpaper, base niri config)
# Nothing is duplicated between the two, so retheming the main tree also
# retheme this install.
#
# Usage:  ./install.sh [--skip-packages] [--skip-fonts] [--yes]

set -euo pipefail

SKIP_PACKAGES=0
SKIP_FONTS=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-packages) SKIP_PACKAGES=1 ;;
        --skip-fonts)    SKIP_FONTS=1 ;;
        --yes|-y)        ASSUME_YES=1 ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's|^# \{0,1\}||'
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

if [[ $ASSUME_YES -eq 0 ]]; then
    cat <<EOF

This will install the Kumori (Precision Overcast) niri + DankMaterialShell
desktop for user '$USER'.

It will write to:
  $CFG/niri  $CFG/DankMaterialShell  $CFG/ghostty  $CFG/gtk-3.0  $CFG/gtk-4.0
  $HOME/.local/share/{icons,fonts,backgrounds}

Existing files in those config dirs are backed up to <dir>.bak-$STAMP first.

EOF
    read -r -p "Continue? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

#############################################
## 1. Packages
#############################################

# Packages that differ from the Fedora build.sh list:
#   adw-gtk3-theme      -> adw-gtk-theme
#   adwaita-cursor-theme-> adwaita-cursors
#   noctalia-shell      -> dms-shell (+ dgop for the system-monitor widgets)
#   ImageMagick         -> dropped (only needed to *generate* the theme, not run it)
#   sddm, cage          -> dropped (CachyOS already ships and configures SDDM)
# cliphist is new: DMS's clipboard panel needs it.
CORE_PKGS=(
    niri
    xwayland-satellite
    ghostty
    zsh
    wl-clipboard
    cliphist
    brightnessctl
    ddcutil
    wlr-randr
    wlsunset
    playerctl
    mate-polkit
    adw-gtk-theme
    adwaita-cursors
    xdg-desktop-portal-gtk
    xdg-desktop-portal-gnome
    nautilus
    firefox
)

# These may live in the AUR depending on how current your CachyOS repos are.
# dms-shell pulls quickshell in as a dependency, so it is not listed separately.
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
    # Check names before handing the whole list to pacman, so a single renamed
    # package produces a clear message instead of a bulk depsolve failure.
    # Most likely to drift: adw-gtk-theme and adwaita-cursors, which are named
    # adw-gtk3-theme / adwaita-cursor-theme on Fedora.
    missing=()
    for pkg in "${CORE_PKGS[@]}"; do
        pacman -Si "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "not found in your configured repos: ${missing[*]}"
        warn "Search for the current name with:  pacman -Ss <name>"
        if [[ $ASSUME_YES -eq 0 ]]; then
            read -r -p "Install the rest anyway? [y/N] " reply
            [[ "$reply" =~ ^[Yy]$ ]] || die "Aborted. Fix the package names in CORE_PKGS and re-run."
        fi
        # Drop the unknown names so the rest can still install.
        for m in "${missing[@]}"; do
            for i in "${!CORE_PKGS[@]}"; do
                [[ "${CORE_PKGS[$i]}" == "$m" ]] && unset 'CORE_PKGS[i]'
            done
        done
        CORE_PKGS=("${CORE_PKGS[@]}")
    fi

    msg "Installing packages from the official repos…"
    [[ ${#CORE_PKGS[@]} -gt 0 ]] && sudo pacman -S --needed "${CORE_PKGS[@]}"

    for pkg in "${MAYBE_AUR_PKGS[@]}"; do
        if pacman -Si "$pkg" >/dev/null 2>&1; then
            msg "Installing $pkg from the repos…"
            sudo pacman -S --needed "$pkg"
        elif helper="$(aur_helper)"; then
            msg "$pkg is not in the repos; installing from the AUR with $helper…"
            "$helper" -S --needed "$pkg"
        else
            warn "$pkg is not in your repos and no AUR helper (paru/yay) was found."
            warn "Install it manually — see https://danklinux.com/docs/dankmaterialshell/installation"
        fi
    done
fi

#############################################
## 2. Brand fonts (Precision Overcast)
#############################################
# Schibsted Grotesk (sans) + Geist / Geist Mono are not in the Arch repos.
# Same upstream variable TTFs (all OFL) the image build fetches.

if [[ $SKIP_FONTS -eq 1 ]]; then
    msg "Skipping fonts (--skip-fonts)."
else
    FONTDIR="$HOME/.local/share/fonts/kumori"
    msg "Fetching brand fonts into $FONTDIR…"
    mkdir -p "$FONTDIR"
    curl -fL --retry 3 -o "$FONTDIR/GeistMono.ttf" \
        "https://github.com/google/fonts/raw/main/ofl/geistmono/GeistMono%5Bwght%5D.ttf"
    curl -fL --retry 3 -o "$FONTDIR/Geist.ttf" \
        "https://github.com/google/fonts/raw/main/ofl/geist/Geist%5Bwght%5D.ttf"
    curl -fL --retry 3 -o "$FONTDIR/SchibstedGrotesk.ttf" \
        "https://github.com/google/fonts/raw/main/ofl/schibstedgrotesk/SchibstedGrotesk%5Bwght%5D.ttf"
    fc-cache -f "$FONTDIR" >/dev/null
fi

#############################################
## 3. Config files
#############################################

backup() {
    [[ -e "$1" ]] || return 0
    mv "$1" "$1.bak-$STAMP"
    warn "backed up $(basename "$1") -> $(basename "$1").bak-$STAMP"
}

mkdir -p "$CFG"

# --- niri: base config from the main tree, DMS overrides from here ---
msg "Installing niri config…"
backup "$CFG/niri"
mkdir -p "$CFG/niri/cfg"
install -m644 "$SRC_SKEL/.config/niri/config.kdl" "$CFG/niri/config.kdl"
# Identical to the Fedora image — no DMS/Arch differences.
for f in animation.kdl display.kdl input.kdl layout.kdl; do
    install -m644 "$SRC_SKEL/.config/niri/cfg/$f" "$CFG/niri/cfg/$f"
done
# DMS/Arch-specific: shell autostart, dms ipc keybinds, matugen kill-switch,
# quickshell layer rule, Arch polkit path.
for f in autostart.kdl keybinds.kdl misc.kdl rules.kdl; do
    install -m644 "$HERE/skel/.config/niri/cfg/$f" "$CFG/niri/cfg/$f"
done

# --- shell-agnostic theming, straight from the main tree ---
msg "Installing ghostty + GTK theming…"
for d in ghostty gtk-3.0 gtk-4.0; do
    backup "$CFG/$d"
    mkdir -p "$CFG/$d"
    cp -R "$SRC_SKEL/.config/$d/." "$CFG/$d/"
done

# --- DankMaterialShell ---
# settings.json is owned by DMS at runtime (bar layout, widget state, …), so if
# one already exists we merge our two theme keys into it rather than clobber it.
msg "Installing DankMaterialShell theme…"
DMSDIR="$CFG/DankMaterialShell"
mkdir -p "$DMSDIR"
install -m644 "$HERE/skel/.config/DankMaterialShell/precision-overcast.json" \
    "$DMSDIR/precision-overcast.json"

THEME_PATH="$DMSDIR/precision-overcast.json"
if [[ -f "$DMSDIR/settings.json" ]]; then
    if command -v jq >/dev/null 2>&1; then
        tmp="$(mktemp)"
        jq --arg p "$THEME_PATH" \
           '.currentThemeName = "custom" | .customThemeFile = $p' \
           "$DMSDIR/settings.json" > "$tmp" && mv "$tmp" "$DMSDIR/settings.json"
        msg "merged theme keys into your existing DMS settings.json"
    else
        backup "$DMSDIR/settings.json"
        sed "s|__HOME__|$HOME|g" \
            "$HERE/skel/.config/DankMaterialShell/settings.json" > "$DMSDIR/settings.json"
        warn "jq not installed — wrote a fresh settings.json and backed up the old one."
        warn "Install jq and re-run to merge instead, or restore your bar layout by hand."
    fi
else
    sed "s|__HOME__|$HOME|g" \
        "$HERE/skel/.config/DankMaterialShell/settings.json" > "$DMSDIR/settings.json"
fi

#############################################
## 4. Cursor theme, wallpaper
#############################################

msg "Installing the Simp1e Precision Overcast cursor theme…"
ICONDIR="$HOME/.local/share/icons"
mkdir -p "$ICONDIR"
backup "$ICONDIR/Simp1e-Precision-Overcast"
cp -R "$SRC_SHARE/icons/Simp1e-Precision-Overcast" "$ICONDIR/"

msg "Installing the wallpaper…"
WALLDIR="$HOME/.local/share/backgrounds/kumori"
mkdir -p "$WALLDIR"
cp "$SRC_SHARE/backgrounds/kumori/kumori.jpg" "$WALLDIR/"

#############################################
## 5. Appearance defaults
#############################################
# The image ships these as a system dconf db (/etc/dconf/db/local.d). Here we
# write them to the user's own dconf db instead — same effect, no sudo. Under
# niri there is no GNOME settings daemon, so without this libadwaita apps render
# light and the Precision Overcast gtk.css recolor looks inconsistent.

if command -v gsettings >/dev/null 2>&1; then
    msg "Setting GTK appearance defaults…"
    # Deliberately non-fatal: a missing schema must not abort an otherwise
    # complete install (and must not skip the "next steps" notes below).
    gset() {
        gsettings set org.gnome.desktop.interface "$1" "$2" 2>/dev/null \
            || warn "could not set $1 (schema missing?) — set it by hand if apps render light."
    }
    gset color-scheme 'prefer-dark'
    gset gtk-theme 'adw-gtk3-dark'
    gset cursor-theme 'Simp1e-Precision-Overcast'
    gset font-name 'Schibsted Grotesk 10'
    gset monospace-font-name 'Geist Mono 11'
    # Closest built-in accent enum to Glacier; exact hex comes from gtk.css.
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
  1. Log out and pick the "niri" session in SDDM.
  2. Set the wallpaper once — DMS does not read a directory the way noctalia did:
       dms ipc call wallpaper set $WALLDIR/kumori.jpg
  3. Set the shell fonts in DMS: Settings -> Appearance, choose
     "Schibsted Grotesk" (UI) and "Geist Mono" (fixed). These are not set by
     this script because the DMS settings.json key names are not documented.

Notes:
  - Static theming: DMS_DISABLE_MATUGEN=1 is set in niri's environment block
    (cfg/misc.kdl). Without it, DMS regenerates its palette from the wallpaper
    and overwrites Precision Overcast.
  - If DMS's "Application Theming" feature is on, it may overwrite
    ~/.config/gtk-3.0/gtk.css. Turn it off to keep the hand-tuned recolor.
  - Verify the polkit agent path (cfg/autostart.kdl) if auth dialogs never appear:
       pacman -Ql mate-polkit | grep agent-1
  - Backups from this run are suffixed .bak-$STAMP

EOF
