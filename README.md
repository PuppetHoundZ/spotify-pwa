#WHAT THIS SCRIPT DOES:
Installs a Chromium PWA shortcut to open.spotify.com. No compilation.
Uses pre-installed Chromium. RAM cache in /dev/shm. Embedded SVG icon.
This is the canonical preferred Spotify solution — lightweight and simple.
Modelled on Botspot's WhatsApp Pi-Apps install pattern.
Ref: [https://github.com/Botspot/pi-apps/blob/master/apps/WhatsApp/install](https://github.com/Botspot/pi-apps/blob/master/apps/WhatsApp/install)

KEY PATHS:
/usr/local/bin/spotify-web                           launcher script (sudo)
/usr/local/share/applications/spotify-web.desktop   desktop entry (sudo)
~/.local/share/icons/hicolor/scalable/apps/spotify-web.svg
~/.config/webapps/spotify-web/                       isolated Chromium profile
/dev/shm/spotify-web-cache/                          RAM cache (volatile)

ICON:
SVG in hicolor/scalable/apps (user-space, no sudo).
Taskbar icon on labwc is unfixable — Better Chromium's zzzz_combine_values
wrapper overrides all Chromium window identity system-wide before labwc sees
it. App menu icon works correctly. Do NOT retry taskbar fix.

CANONICAL FLAG SOURCE:
This file is the single source of truth for Spotify Web Chromium flags.
Spotiapps_suite.sh SW_FLAGS must mirror these exactly. Always update here
first, then sync the suite. Never update suite flags independently.

FLAG DECISIONS — do not reverse without explicit request:
--disable-features=MediaRouter : ABSENT — disabling it breaks Chromecast.
--disable-web-resources        : REMOVED — no-op on Chromium 120+.
--disable-translate            : REMOVED — CLI switch removed from Chromium;
covered by TranslateUI in --disable-features.
--enable-accelerated-video-decode : PRESENT — VA-API hardware decode on
Pi 4 VideoCore VI. Pairs with UseChromeOSDirectVideoDecoder disabled.

FLAG REQUIREMENTS:
--js-flags MUST be quoted: "--max-old-space-size=192 --optimize-for-size"
Unquoted, only the first V8 flag takes effect.
--ozone-platform=wayland : Required for native Wayland under labwc.
--user-data-dir : CRITICAL — isolated Chromium profile; without it Chromium
reuses other PWA sessions (YouTube, Claude) and opens a tab instead.

ENVIRONMENT:
Pi 4, Pi OS Trixie (Debian 13 arm64), labwc Wayland, 800x480 DSI + 1080p HDMI.
Better Chromium (Botspot) injects flags via /etc/chromium.d/ — affects all
Chromium launches. Pi OS base rpi-chromium-mods only sets
--force-renderer-accessibility and --enable-remote-extensions.
