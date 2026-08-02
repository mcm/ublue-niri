# Kumori on CachyOS (niri + DankMaterialShell)

A side-door port of the Kumori desktop to CachyOS/Arch, with
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) in place of
noctalia. The main repo is unaffected — it still builds the Fedora/bootc image
with niri + noctalia. This directory is additive.

Two independent changes from the image, done together here:

| | Image (`build_files/`) | Here (`_cachyos/`) |
| --- | --- | --- |
| Distro | Fedora atomic (bluefin-dx, bootc) | CachyOS / Arch |
| Shell | noctalia (Quickshell) | DankMaterialShell (Quickshell) |
| Install unit | baked into `/etc/skel` at build time | per-user, into `$HOME` |
| Theme source | `noctalia/colorschemes/…json` | `DankMaterialShell/precision-overcast.json` |

Precision Overcast itself is unchanged. The palette, the ghostty colors, the GTK
recolor, and the cursor theme are the same files the image ships.

## Install

On the CachyOS machine, with the repo checked out:

```
git clone https://github.com/mcm/kumori
cd kumori/_cachyos
./install.sh
```

Flags: `--skip-packages`, `--skip-fonts`, `--yes`.

The script is per-user and only calls `sudo` for `pacman`. Everything it writes
lands in `~/.config` and `~/.local/share`. Existing configs in those locations
are moved aside to `<name>.bak-<timestamp>` before anything is written, so a
re-run is safe and reversible.

Then log out and pick the **niri** session.

## What's in here vs. sourced from the main tree

Only files that actually differ live in this directory. Everything else is read
out of `../build_files/system_files/` at install time, so retheming the main tree
also retheme this install — there is no second copy to keep in sync.

**In `_cachyos/skel/`:**

| File | Why it differs |
| --- | --- |
| `niri/cfg/autostart.kdl` | Spawns `dms run` instead of `qs -c noctalia-shell`; Arch's `/usr/lib` polkit path instead of Fedora's `/usr/libexec`; adds `cliphist`. |
| `niri/cfg/keybinds.kdl` | All shell binds rewritten from `qs -c noctalia-shell ipc call …` to `dms ipc call …`, using plain `spawn` (no shell process per keypress). Adds `Mod+V` clipboard and `Mod+N` notification center. |
| `niri/cfg/misc.kdl` | Adds `DMS_DISABLE_MATUGEN "1"` to the environment block. Cursor-size comment rewritten (the image's 24-vs-48 note was about its own SDDM/cage greeter). |
| `niri/cfg/rules.kdl` | Wallpaper layer rule matches `^quickshell$` instead of `^noctalia-wallpaper*`. |
| `DankMaterialShell/precision-overcast.json` | The palette, mapped to DMS's Material 3 role names. |
| `DankMaterialShell/settings.json` | Two keys that point DMS at the theme file. |

**Sourced from `../build_files/system_files/`:** `config.kdl` and
`cfg/{animation,display,input,layout}.kdl`, the ghostty config, both GTK
`gtk.css` + `settings.ini` pairs, the Simp1e Precision Overcast cursor theme, and
the wallpaper.

**The greeter is ported**, with changes — see "The SDDM greeter" below.

## Install target

This assumes a CachyOS install where **no desktop was selected** in the
installer. `install.sh` installs the entire graphical stack itself: compositor,
shell, display manager, pipewire, NetworkManager, portals, keyring, and base
fonts. Nothing is inherited from a CachyOS desktop edition.

Installing on top of an existing CachyOS desktop edition works too, but the Niri
edition in particular carries a trap — see "quickshell, not noctalia-qs" below.

## The SDDM greeter

Ported, but not verbatim. Three changes were needed, each found the hard way:

**weston, not cage.** The image runs `cage -s` because Fedora's weston kiosk
shell drew no cursor. Neither half of that holds on Arch: weston renders the
cursor correctly, and `cage -s` with no application argument has *no exit
condition* — it keeps running after the greeter client disconnects, holds DRM
master, and the niri session comes up to a frozen screen showing a stale frame.
The comment in the image's config describing the bare-compositor behavior as a
feature is describing the bug.

**`QtVersion=6` in `metadata.desktop`.** SDDM 0.21+ runs a theme under the *Qt5*
greeter binary unless the metadata says otherwise. Arch ships Qt6 only, so
`/usr/bin/sddm-greeter` doesn't exist and the greeter exits 127 immediately —
a black screen with a cursor, and nothing in the journal but an exit code.
Fixed in the shared tree, since `Main.qml` uses Qt6-only imports and the theme
always required this.

**`99-` not `10-`.** SDDM loads `/usr/lib/sddm/sddm.conf.d/*`, then
`/etc/sddm.conf.d/*` (both alphabetically), then `/etc/sddm.conf` last, with
later winning. A `10-` prefix loses to nearly anything a distro ships.
`/etc/sddm.conf` beats every drop-in regardless; `install.sh` warns if one
exists with conflicting keys. Note that `/etc/sddm.conf.d/` is not created by
the `sddm` package — the script creates it.

**Assets must be system-wide.** The greeter runs as the `sddm` user and cannot
read `$HOME`. Fonts, the cursor theme, and the wallpaper all install to
`/usr/share`, not `~/.local/share`. A greeter with none of them still renders —
it just falls back to a default sans, the default arrow cursor, and no
wallpaper, which reads as "the theme didn't apply."

Skip all of it with `--no-greeter`.

## quickshell, not noctalia-qs

`noctalia-qs` declares `Provides: quickshell quickshell-git`. If it's installed —
and it is, on the CachyOS Niri edition — then `pacman -S dms-shell` finds its
quickshell dependency already satisfied and never installs the real package. DMS
then runs against a much older shell, and fails in a way that looks like
anything but a version problem: the service layer registers fine while the
entire UI layer silently doesn't. The bar draws and responds to hover, clicks do
nothing, and `dms ipc call spotlight toggle` returns "Target not found."

`install.sh` names `quickshell` explicitly and refuses to run if `/usr/bin/qs`
is owned by anything else. To fix it by hand:

```
sudo pacman -Rdd noctalia-qs      # -Rdd: don't cascade into cachyos-niri-noctalia
sudo pacman -S quickshell
```

Note that `pacman -S --needed` does **not** re-mark an already-installed
dependency as explicit, so packages pulled in by a CachyOS desktop metapackage
stay dependencies and remain exposed to `-Rs` cascades. The script passes
`--asexplicit` for this reason.

## The palette mapping

DMS custom themes are a fixed set of Material 3 role names, so the port is a
mapping rather than a translation. Every value below is an existing Precision
Overcast token except one:

| DMS role | Token | Hex |
| --- | --- | --- |
| `primary`, `surfaceTint`, `info` | glacier-300 | `#8eb5cc` |
| `primaryText` | slate-900 (text *on* the light accent) | `#131a26` |
| `primaryContainer` | glacier-500 | `#4a7d9b` |
| `secondary`, `surfaceVariantText` | text-secondary | `#a8b3c4` |
| `surface`, `background` | slate-900 | `#131a26` |
| `surfaceText`, `backgroundText` | text-primary | `#e2e7ee` |
| `surfaceVariant`, `surfaceContainer` | slate-800 | `#1f2937` |
| `surfaceContainerHigh` | selection bg | `#2a3445` |
| `surfaceContainerHighest` | **derived** — see below | `#354152` |
| `outline` | slate-600 | `#54637a` |
| `error` | rust | `#b47362` |
| `warning` | amber | `#c9a368` |

`surfaceContainerHighest` is the one invented value: Precision Overcast defines
three slate steps (`#131a26` → `#1f2937` → `#2a3445`) and M3 wants a fourth.
`#354152` continues that ramp. Adjust to taste — it's the background of the
most-elevated surfaces (menus, raised cards).

## Gotchas

**Matugen will eat your theme.** DMS regenerates its entire palette from the
current wallpaper by default, which silently overwrites Precision Overcast on
every wallpaper change. `DMS_DISABLE_MATUGEN "1"` in `cfg/misc.kdl`'s environment
block is what prevents this. It's set in the *session* environment rather than
wrapping `dms run`, so it also applies to `dms` invoked from a terminal.

**DMS may want to own your GTK config.** Its "Application Theming" feature writes
GTK/Qt configs from the active palette and can overwrite the hand-tuned
`~/.config/gtk-3.0/gtk.css`. Leave that feature off.

**Fonts aren't set programmatically.** The DMS `settings.json` key names for UI
and fixed-width fonts aren't documented, so the script doesn't guess at them —
inventing a key would either do nothing or break the file. Set Schibsted Grotesk
and Geist Mono in DMS's own settings UI after first login. The fonts themselves
are installed to `~/.local/share/fonts/kumori`.

**The wallpaper needs setting once.** noctalia read a wallpaper *directory* from
its settings; DMS doesn't work that way. After first login:

```
dms ipc call wallpaper set ~/.local/share/backgrounds/kumori/kumori.jpg
```

**Verify the polkit path.** If authentication dialogs never appear, check that
the Arch path in `cfg/autostart.kdl` is right for your install:

```
pacman -Ql mate-polkit | grep agent-1
```

**Two package names differ from Fedora** and are the most likely thing to drift:
`adw-gtk-theme` (Fedora: `adw-gtk3-theme`) and `adwaita-cursors` (Fedora:
`adwaita-cursor-theme`). The script checks every name against your repos before
installing and tells you which ones it couldn't find rather than failing the
whole transaction.

**`dms-shell` / `dgop` may come from the AUR** depending on how current your
CachyOS repos are. The script checks the official repos first and falls back to
`paru`/`yay` if either is missing.

## What you give up coming from noctalia

`noctalia/settings.json` is ~600 lines of tuning — bar widget layout, dock,
weather and calendar cards, control-center shortcuts — and none of it transfers.
DMS has equivalents for most of it, but you're re-tuning the bar by hand.

## References

- [DMS custom theme format](https://github.com/AvengeMedia/DankMaterialShell/blob/master/docs/CUSTOM_THEMES.md)
- [DMS keybinds & IPC](https://danklinux.com/docs/dankmaterialshell/keybinds-ipc)
- [DMS compositor setup](https://danklinux.com/docs/dankmaterialshell/compositors)
- [DMS installation](https://danklinux.com/docs/dankmaterialshell/installation)
- [DMS advanced configuration](https://danklinux.com/docs/dankmaterialshell/advanced-configuration)
