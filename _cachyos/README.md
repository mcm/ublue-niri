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

**Not ported:** the SDDM `precision-overcast` greeter theme and
`sddm.conf.d/10-kumori.conf`. CachyOS ships and configures its own SDDM; adopting
ours means resolving a `[Theme] Current` conflict. Both files port cleanly if you
want them — `sddm` and `cage` are both in the Arch repos.

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
