# Kumori

An atomic Fedora desktop built as a [bootc](https://github.com/bootc-dev/bootc)
image: [Bluefin-dx](https://projectbluefin.io/) underneath, the
[niri](https://github.com/YaLTeR/niri) scrollable-tiling compositor and the
[noctalia](https://github.com/noctalia-dev/noctalia-shell) shell on top, themed
end to end with **Precision Overcast**.

The image is rebuilt and published as a signed OCI image. Installed systems track
it and update atomically with `bootc`; rollbacks are a single command.

```
ghcr.io/mcm/kumori:latest
```

## What's inside

- **Base:** `ghcr.io/ublue-os/bluefin-dx:stable` — the developer edition of
  Bluefin (container tooling, virtualization, the Bluefin developer stack).
- **Compositor:** niri, from the `yalter/niri` COPR. It is the only session
  offered at login; GNOME remains installed but its session entries are hidden.
- **Shell:** noctalia (Quickshell) — bar, launcher, notifications, OSD, control
  center, lock screen, and wallpaper management in one program.
- **Terminal:** ghostty. **Login shell:** zsh (default for new accounts).
- **Theme:** Precision Overcast — a calm, arctic register with a single Glacier
  accent. Dark by default. Carried through the noctalia color scheme, the
  ghostty palette, and GTK. Fonts: Schibsted Grotesk (sans) and Geist Mono.
- **Auth:** the MATE PolicyKit agent (offline; no network-fetched plugin).

Configuration is seeded from `/etc/skel`, so a freshly created user account
inherits the full niri + noctalia + ghostty setup.

## Install

### Rebase an existing atomic system

From any Fedora atomic / Universal Blue system (Silverblue, Bluefin, Bazzite, …):

```
sudo bootc switch ghcr.io/mcm/kumori:latest
sudo systemctl reboot
```

Note: rebasing does not touch an existing user's `~/.config`, so the niri
configs (which live in `/etc/skel`) are not applied to accounts that already
exist. Either create a fresh user, or copy them in once:

```
cp -rn /etc/skel/.config/{niri,noctalia,ghostty,gtk-3.0,gtk-4.0} ~/.config/
```

Roll back with `sudo bootc rollback` and reboot.

### Install from an ISO

The `Build disk images` workflow produces an installer ISO (and a qcow2) via
[bootc-image-builder](https://github.com/osbuild/bootc-image-builder). Run it
from the Actions tab (`platform: amd64`), download the `kumori.iso` artifact,
and write it to a USB stick. The Anaconda installer prompts for a user account;
that account picks up the `/etc/skel` configuration.

## Images are signed

Every image is signed with [cosign](https://github.com/sigstore/cosign). The
public key is `cosign.pub` in this repository. Verify a pull with:

```
cosign verify --key cosign.pub ghcr.io/mcm/kumori
```

## Build it yourself

Local build (requires `podman` and `just`):

```
just build                 # build the container image
just build-qcow2           # build a bootable VM disk
just run-vm-qcow2          # boot it in a VM
```

CI builds the same image on every push to `main` and on a daily schedule, then
signs and pushes it to GHCR.

## Optional: the CachyOS kernel

`build_files/optional/cachyos-kernel.sh` swaps in the
[CachyOS kernel](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/).
It is **off by default** because that kernel is not signed with the Fedora /
Universal Blue Secure Boot key — enabling it means disabling Secure Boot or
enrolling your own keys. Review the script before turning it on.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Containerfile` | Image definition; sets the base and runs the build script. |
| `build_files/build.sh` | Packages, brand fonts, the Kumori rebrand, theming, GDM session setup. |
| `build_files/system_files/` | Files copied into the image (the `/etc/skel` niri, noctalia, ghostty, and GTK configs). |
| `build_files/optional/cachyos-kernel.sh` | Opt-in CachyOS kernel swap. |
| `disk_config/` | bootc-image-builder configs: `disk.toml` (qcow2), `iso.toml` (installer ISO). |
| `_cachyos/` | Side port: the same desktop on CachyOS/Arch with DankMaterialShell instead of noctalia. Not part of the image build. |
| `.github/workflows/` | `build.yml` (container image), `build-disk.yml` (qcow2 + ISO). |
| `ATTRIBUTION.md` | Third-party attribution and licenses. |

## Credits

The niri and noctalia configuration is derived from
[CachyOS/cachyos-niri-noctalia](https://github.com/CachyOS/cachyos-niri-noctalia)
(GPL-3.0), adapted for Fedora and the Precision Overcast theme. Built from the
Universal Blue [image-template](https://github.com/ublue-os/image-template). See
[`ATTRIBUTION.md`](./ATTRIBUTION.md) for full detail.

Wallpaper: Photo by [Quino Al](https://unsplash.com/@quinoal?utm_source=unsplash&utm_medium=referral&utm_content=creditCopyText) on [Unsplash](https://unsplash.com/photos/photo-of-beach-at-golden-hour-ZuZK8D55_cw?utm_source=unsplash&utm_medium=referral&utm_content=creditCopyText).
