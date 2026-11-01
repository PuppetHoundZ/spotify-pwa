# Spotify Web PWA — Raspberry Pi

Installs a lightweight, tuned Chromium app-window shortcut for the Spotify Web Player (open.spotify.com) on Raspberry Pi OS. No compilation. Uses the Chromium that comes with Pi OS. Isolated profile, cache in RAM, embedded SVG icon. Works with free and Premium Spotify accounts.

This is the canonical, preferred Spotify solution — lightweight and simple. Modelled on Botspot's WhatsApp Pi-Apps install pattern.
Ref: https://github.com/Botspot/pi-apps/blob/master/apps/WhatsApp/install

> Built and tested on a Raspberry Pi 4 (Pi OS Trixie, Debian 13 arm64), labwc Wayland, 7" 800×480 DSI touchscreen + 1080p HDMI.

## Requirements

- Raspberry Pi OS Trixie (Debian 13) with desktop
- Chromium (pre-installed on Pi OS desktop)
- Internet connection
- Optional: the **More RAM** app from Pi-Apps (zram) — if installed, the cache uses compressed RAM at `/zram`

## Install

```bash
chmod +x manage_spotify.sh
./manage_spotify.sh
```

Do **not** run as root. The menu offers:

```
1) Install / Reinstall
2) Uninstall
3) Exit
```

On install you're asked whether to also pin a launcher icon to your Desktop.

## What it does

- Writes a launcher script to `/usr/local/bin/spotify-web` that starts Chromium in app mode (`--app=https://open.spotify.com`) with a separate profile and tuned flags.
- Adds an app-menu entry (Sound & Video → Spotify Web) with an embedded SVG icon.
- Keeps the browser cache in RAM so playback causes no SD card writes.
  - If the Pi-Apps **More RAM** zram drive is mounted and writable at `/zram`, the cache goes to `/zram/spotify-web-cache-$USER` (compressed RAM).
  - Otherwise it uses `/dev/shm/spotify-web-cache`.
  - This is checked each time Spotify starts, so adding or removing More RAM needs no reinstall.
- No keyring password prompt: `--password-store=basic` stops Chromium asking to unlock the keyring. Saved passwords for this Spotify profile only are stored unencrypted on disk (the same way Pi OS Bookworm did).

## Key paths

| What | Where |
|---|---|
| Launcher script (sudo) | `/usr/local/bin/spotify-web` |
| Desktop entry (sudo) | `/usr/local/share/applications/spotify-web.desktop` |
| Icon | `~/.local/share/icons/hicolor/scalable/apps/spotify-web.svg` |
| Isolated Chromium profile | `~/.config/webapps/spotify-web/` |
| RAM cache (with More RAM) | `/zram/spotify-web-cache-$USER/` |
| RAM cache (fallback) | `/dev/shm/spotify-web-cache/` |
| Optional pinned launcher | `~/Desktop/spotify-web.desktop` |

Uninstall removes the launcher, desktop entry, icon, pinned launcher and both cache locations. You're asked before the profile (your Spotify login) is removed.

## Notes for maintainers

### Canonical flag source
`manage_spotify.sh` is the single source of truth for Spotify Web Chromium flags. `Spotiapps_suite.sh` (`SW_FLAGS`) must mirror these exactly. Always update here first, then sync the suite. Never update suite flags independently.

### Flag decisions — do not reverse without explicit request
- `--disable-features=MediaRouter` : ABSENT — disabling it breaks Chromecast.
- `--disable-web-resources` : REMOVED — no-op on Chromium 120+.
- `--disable-translate` : REMOVED — CLI switch removed from Chromium; covered by `TranslateUI` in `--disable-features`.
- `--enable-accelerated-video-decode` : PRESENT — VA-API hardware decode on Pi 4 VideoCore VI. Pairs with `UseChromeOSDirectVideoDecoder` disabled.
- `--password-store=basic` : PRESENT — no keyring prompt in the isolated profile (from Better Chromium's "Disable keyring password prompt" option).

### Flag requirements
- `--js-flags` MUST be quoted: `"--max-old-space-size=192 --optimize-for-size"`. Unquoted, only the first V8 flag takes effect.
- `--ozone-platform=wayland` : Required for native Wayland under labwc.
- `--user-data-dir` : CRITICAL — isolated Chromium profile; without it Chromium reuses other PWA sessions (YouTube, Claude) and opens a tab instead.

### Better Chromium interaction
Better Chromium (Botspot, Pi-Apps) adds flags through `/etc/chromium.d/`, which applies to **every** Chromium launch, including this one. Pi OS's own rpi-chromium-mods only sets `--force-renderer-accessibility` and `--enable-remote-extensions`.
- Better Chromium's `zzzz_combine_values` wrapper merges all `--enable-features` / `--disable-features` arguments into one. Before its 2026-10-18 fix it also split any argument containing spaces, which broke the quoted `--js-flags` value. Keep Better Chromium up to date.
- If Better Chromium's "Performance Improvements" is enabled, some of its flags overlap with ours (for example `--num-raster-threads`). Check `chrome://version` in the Spotify window to see the final command line.

### Icon
The SVG icon lives in `hicolor/scalable/apps` (user space, no sudo). The app menu icon works correctly. The labwc taskbar shows the wrong icon; the cause has not been confirmed (Better Chromium's wrapper does not change `--class`). Do NOT retry a taskbar fix.

## References

- Botspot WhatsApp install pattern: https://github.com/Botspot/pi-apps/blob/master/apps/WhatsApp/install
- Better Chromium (Pi-Apps): https://github.com/Botspot/pi-apps/tree/master/apps/Better%20Chromium
- Better Chromium space-in-flags fix: https://github.com/Botspot/pi-apps/commit/83ad32a4
- Better Chromium keyring option: https://github.com/Botspot/pi-apps/commit/17938ced
- Better Chromium zram cache: https://github.com/Botspot/pi-apps/commit/c98a30a1
- Chromium password storage on Linux: https://chromium.googlesource.com/chromium/src/+/main/docs/linux/password_storage.md
- `zramctl` manual: https://man7.org/linux/man-pages/man8/zramctl.8.html
- Raspberry Pi OS Trixie release notes: https://www.raspberrypi.com/news/raspberry-pi-os-trixie/

## Disclaimer

This script is provided as-is, free of charge, as part of an open source community effort for Raspberry Pi users. It is not affiliated with or endorsed by Spotify AB, Raspberry Pi Ltd, the Chromium project or Pi-Apps. Use it at your own risk. No warranty is expressed or implied.

Licensed under the MIT License — see [LICENSE](LICENSE).
