#!/bin/bash
# =============================================================================
# manage_spotify.sh
# Spotify Web Shortcut Manager — Raspberry Pi 4
# Version: 1.5.6
# Status: 🟡 Pending hardware test
# Last updated: 2026-06-25
#
# Installs an optimized Chromium PWA shortcut to open.spotify.com.
# No compilation. Uses pre-installed Chromium. RAM cache in /dev/shm.
# Embedded SVG icon. Works with free and Premium Spotify accounts.
# This is the canonical preferred Spotify solution — lightweight and simple.
#
# Requirements:
#   - Raspberry Pi OS Trixie (Debian 13 arm64)
#   - Chromium (pre-installed on Pi OS desktop)
#   - Internet connection
#
# Usage:
#   chmod +x manage_spotify.sh && ./manage_spotify.sh
#   Do NOT run as root.
# =============================================================================
#
# AI REFERENCE NOTES
# ──────────────────────────────────────────────────────────────────────────
#
# WHAT THIS SCRIPT DOES:
#   Installs a Chromium PWA shortcut to open.spotify.com. No compilation.
#   Uses pre-installed Chromium. RAM cache in /dev/shm. Embedded SVG icon.
#   This is the canonical preferred Spotify solution — lightweight and simple.
#   Modelled on Botspot's WhatsApp Pi-Apps install pattern.
#   Ref: https://github.com/Botspot/pi-apps/blob/master/apps/WhatsApp/install
#
# KEY PATHS:
#   /usr/local/bin/spotify-web                          # launcher script (sudo)
#   /usr/local/share/applications/spotify-web.desktop  # desktop entry (sudo)
#   ~/.local/share/icons/hicolor/scalable/apps/spotify-web.svg
#   ~/.config/webapps/spotify-web/                      # isolated Chromium profile
#   /dev/shm/spotify-web-cache/                         # RAM cache (volatile)
#
# ICON:
#   SVG in hicolor/scalable/apps (user-space, no sudo).
#   Taskbar icon on labwc is unfixable — Better Chromium's zzzz_combine_values
#   wrapper overrides all Chromium window identity system-wide before labwc sees
#   it. App menu icon works correctly. Do NOT retry taskbar fix.
#
# CANONICAL FLAG SOURCE:
#   This file is the single source of truth for Spotify Web Chromium flags.
#   Spotiapps_suite.sh SW_FLAGS must mirror these exactly. Always update here
#   first, then sync the suite. Never update suite flags independently.
#
# FLAG DECISIONS — do not reverse without explicit request:
#   --disable-features=MediaRouter : ABSENT — disabling it breaks Chromecast.
#   --disable-web-resources        : REMOVED — no-op on Chromium 120+.
#   --disable-translate            : REMOVED — CLI switch removed from Chromium;
#     covered by TranslateUI in --disable-features.
#   --enable-accelerated-video-decode : PRESENT — VA-API hardware decode on
#     Pi 4 VideoCore VI. Pairs with UseChromeOSDirectVideoDecoder disabled.
#
# FLAG REQUIREMENTS:
#   --js-flags MUST be quoted: "--max-old-space-size=192 --optimize-for-size"
#     Unquoted, only the first V8 flag takes effect.
#   --ozone-platform=wayland : Required for native Wayland under labwc.
#   --user-data-dir : CRITICAL — isolated Chromium profile; without it Chromium
#     reuses other PWA sessions (YouTube, Claude) and opens a tab instead.
#
# ENVIRONMENT:
#   Pi 4, Pi OS Trixie (Debian 13 arm64), labwc Wayland, 800x480 DSI + 1080p HDMI.
#   Better Chromium (Botspot) injects flags via /etc/chromium.d/ — affects all
#   Chromium launches. Pi OS base rpi-chromium-mods only sets
#   --force-renderer-accessibility and --enable-remote-extensions.
#
# VERSION HISTORY:
#   v1.5.6 (2026-06) -- Added optional desktop launcher pin prompt (y/N) on
#     install, matching backlight/webapps pattern. write_desktop_launcher()
#     writes to XDG_DESKTOP_DIR (~Desktop). Uninstall cleans it up.
#   v1.5.5 (2026-06) — Header updated to current project style. Added colored
#     installation status display to menu (mirrors manage_webapps.sh pattern).
#     No functional changes to install/uninstall/launcher/flags.
#   v1.5.4 (2026-06) — Added --disable-component-extensions-with-background-pages.
#     Stops built-in Chromium extensions (PDF viewer, Cast helper) from running
#     persistent background pages. Brings flag parity with Spotiapps_suite.sh.
#   v1.5.3 (2026-06) — Added --disable-stack-profiler. Fixed missing
#     gtk-update-icon-cache call on install. Fixed update-desktop-database path
#     to /usr/local/share/applications (was incorrectly ~/.local/share/applications).
#   v1.5.0 (2026-06) — Added --enable-accelerated-video-decode and
#     --disable-features=UseChromeOSDirectVideoDecoder (VA-API path, Pi 4).
#   v1.4.0 (2026-06) GOLD — --user-data-dir isolated profile. Fixed binary
#     chromium-browser -> chromium. SVG icon. /usr/local paths (Botspot pattern).
#   v1.3.0 (2026-06) — Removed stale flags. Fixed --js-flags quoting.
#     Added --ozone-platform=wayland and GlobalMediaControls,ChromeLabs disable.
#   v1.2.0 — Initial stable release with RAM cache and embedded SVG icon.
# =============================================================================

SCRIPT_VERSION="1.5.6"

# ── Colors ────────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

# ── Paths ─────────────────────────────────────────────────────────────────────
LAUNCHER="/usr/local/bin/spotify-web"
DESKTOP_FILE="/usr/local/share/applications/spotify-web.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
ICON_NAME="spotify-web"
ICON_FILE="$ICON_DIR/${ICON_NAME}.svg"
USER_DATA_DIR="$HOME/.config/webapps/spotify-web"
RAM_CACHE_DIR="/dev/shm/spotify-web-cache"
XDG_DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "${HOME}/Desktop")"
DESKTOP_LAUNCHER="${XDG_DESKTOP_DIR}/spotify-web.desktop"

# ── Installation status ───────────────────────────────────────────────────────
# Returns "installed" if all three required files exist, "not installed" otherwise.
app_status() {
    [[ -f "$LAUNCHER" && -f "$DESKTOP_FILE" && -f "$ICON_FILE" ]] \
        && echo "installed" || echo "not installed"
}

# ── RAM cache ─────────────────────────────────────────────────────────────────
ensure_ram_cache() {
    if [ ! -d "$RAM_CACHE_DIR" ]; then
        mkdir -p "$RAM_CACHE_DIR"
        echo "RAM cache directory created: $RAM_CACHE_DIR"
    fi
}

# ── SVG Icon ──────────────────────────────────────────────────────────────────
# Embedded SVG — no internet needed, no dependencies, scales perfectly.
# Colours:
#   Circle fill : #1ED760 — Spotify icon green (lighter, used in actual logo)
#   Arc fill    : #FFFFFF — white arcs on green background
# Shows correctly in app menu/launcher. Taskbar icon is a known unfixable
# issue (Pi OS system flags override Chromium window identity). Do not retry.
write_icon() {
    mkdir -p "$ICON_DIR"
    cat > "$ICON_FILE" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 168 168">
  <circle cx="84" cy="84" r="84" fill="#1ED760"/>
  <path d="M121.4 121.2c-1.5 2.4-4.7 3.2-7.1 1.7
           C93.7 110.1 67.5 107.4 36.4 114.5
           c-2.8.6-5.6-1.1-6.2-3.9-.6-2.8 1.1-5.6 3.9-6.2
           C67.2 97 96.1 100 118.2 112.5c2.4 1.5 3.2 4.7 1.7 7.1h.5z
           M132 95.8c-1.9 3.1-5.9 4.1-9 2.2
           C100.3 82.9 66.4 78.6 39.9 86.7
           c-3.5 1-7.1-.9-8.1-4.4-1-3.5.9-7.1 4.4-8.1
           C63.9 65.2 101.4 70.1 127 86c3.1 1.9 4.1 5.9 2.2 9z
           M133.5 69.3C105.7 52.7 60.4 51.2 34 59.2
           c-4.1 1.2-8.5-1.1-9.8-5.2-1.2-4.1 1.1-8.5 5.2-9.8
           C58.4 35.1 108.4 36.9 140.5 55.9
           c3.8 2.2 5 7 2.8 10.8-2.2 3.8-7 5-10.8 2.8z"
        fill="#fff"/>
</svg>
SVGEOF
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    echo "Icon written: $ICON_FILE"
}

# ── Launcher script ───────────────────────────────────────────────────────────
# Mirrors Botspot's WhatsApp launcher pattern.
# Uses 'chromium' — the correct binary name on Pi OS Trixie.
# --user-data-dir isolates this session from all other Chromium PWAs.
write_launcher() {
    echo "Creating launcher..."
    sudo mkdir -p /usr/local/bin
    cat << EOF | sudo tee "$LAUNCHER" > /dev/null || { echo "Failed to create launcher"; exit 1; }
#!/bin/bash
mkdir -p "\$HOME/.config/webapps/spotify-web"
mkdir -p "$RAM_CACHE_DIR"
exec chromium \
--user-data-dir="\$HOME/.config/webapps/spotify-web" \
--app=https://open.spotify.com \
--app-color=#121212 \
--class=spotify-web \
--ozone-platform=wayland \
--process-per-site \
--renderer-process-limit=1 \
--disk-cache-dir=$RAM_CACHE_DIR \
--disk-cache-size=20971520 \
--media-cache-size=20971520 \
--disable-gpu-shader-disk-cache \
--disable-gpu-program-cache \
--enable-gpu-rasterization \
--enable-accelerated-video-decode \
--num-raster-threads=1 \
--force-prefers-reduced-motion \
--disable-smooth-scrolling \
--disable-threaded-animation \
--disable-threaded-scrolling \
--disable-checker-imaging \
--disable-background-networking \
--disable-background-timer-throttling \
--disable-renderer-backgrounding \
--disable-backgrounding-occluded-windows \
--disable-breakpad \
--disable-crash-reporter \
--disable-component-update \
--disable-updater-scheduler \
--disable-stack-profiler \
--disable-component-extensions-with-background-pages \
--disable-domain-reliability \
--disable-client-side-phishing-detection \
--disable-default-apps \
--no-pings \
--js-flags="--max-old-space-size=192 --optimize-for-size" \
--disable-logging \
--log-level=3 \
--no-crash-upload \
--no-first-run \
--no-default-browser-check \
--disable-sync \
--disable-features=TranslateUI,AutofillAssistant,GlobalMediaControls,ChromeLabs,UseChromeOSDirectVideoDecoder
EOF
    sudo chmod +x "$LAUNCHER" || { echo "Failed to set launcher permissions"; exit 1; }
    echo "Launcher written: $LAUNCHER"
}

# ── Desktop file ──────────────────────────────────────────────────────────────
write_desktop() {
    echo "Creating desktop entry..."
    sudo mkdir -p /usr/local/share/applications
    cat << EOF | sudo tee "$DESKTOP_FILE" > /dev/null || { echo "Failed to create desktop entry"; exit 1; }
[Desktop Entry]
Name=Spotify Web
GenericName=Music Player
Comment=Optimized Spotify Web Player (Raspberry Pi)
Exec=$LAUNCHER
Icon=$ICON_NAME
Type=Application
StartupNotify=false
StartupWMClass=spotify-web
Categories=AudioVideo;Player;Music;
Keywords=spotify;music;streaming;
EOF
    echo "Desktop entry written: $DESKTOP_FILE"
}

# ── Optional desktop launcher (pinned to ~/Desktop) ──────────────────────────
write_desktop_launcher() {
    mkdir -p "${XDG_DESKTOP_DIR}"
    cat > "${DESKTOP_LAUNCHER}" << EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Spotify Web
Comment=Optimized Spotify Web Player (Raspberry Pi)
Exec=${LAUNCHER}
Icon=${ICON_NAME}
Terminal=false
Categories=AudioVideo;Player;Music;
EOF
    chmod +x "${DESKTOP_LAUNCHER}" 2>/dev/null || true
}

# ── Install ───────────────────────────────────────────────────────────────────
install_shortcut() {
    echo "Installing Spotify Web..."
    write_icon
    write_launcher
    write_desktop
    ensure_ram_cache
    sudo touch /usr/local/share/icons 2>/dev/null || true
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    sudo update-desktop-database /usr/local/share/applications 2>/dev/null || true

    local ans_dl
    read -r -p "Add a launcher icon to the desktop? [y/N]: " ans_dl
    if [[ "${ans_dl,,}" == "y" ]]; then
        write_desktop_launcher
        echo "Desktop launcher icon added to ${XDG_DESKTOP_DIR}."
    else
        rm -f "${DESKTOP_LAUNCHER}"
        echo "Desktop launcher skipped."
    fi

    echo ""
    echo "========================================"
    echo "  Done! Spotify Web installed."
    echo ""
    echo "  Optimizations active:"
    echo "    • Isolated Chromium profile — no session reuse"
    echo "    • Cache in RAM (/dev/shm) — no SD writes"
    echo "    • GPU shader/program cache disabled"
    echo "    • Crash reporting and telemetry disabled"
    echo "    • Animations and background activity suppressed"
    echo "    • V8 heap tuned (192 MB, optimize-for-size)"
    echo ""
    echo "  Known issue: taskbar shows wrong icon (Pi OS system"
    echo "  limitation — unfixable without modifying system files)."
    echo "  App menu icon and app itself work correctly."
    echo "========================================"
}

# ── Uninstall ─────────────────────────────────────────────────────────────────
uninstall_shortcut() {
    echo "Removing Spotify Web..."
    sudo rm -f "$DESKTOP_FILE" "$LAUNCHER"
    rm -f "$ICON_FILE"
    rm -f "${DESKTOP_LAUNCHER}"
    rm -rf "$RAM_CACHE_DIR"
    sudo touch /usr/local/share/icons 2>/dev/null || true
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    sudo update-desktop-database /usr/local/share/applications 2>/dev/null || true

    echo ""
    read -rp "Also remove Spotify profile/login data ($USER_DATA_DIR)? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$USER_DATA_DIR"
        echo "Profile data removed."
    else
        echo "Profile data kept at: $USER_DATA_DIR"
    fi

    echo "Done! Spotify Web removed."
}

# ── Menu ──────────────────────────────────────────────────────────────────────
show_menu() {
    clear

    local status colour
    status=$(app_status)
    [[ "$status" == "installed" ]] && colour="$GREEN" || colour="$RED"

    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}  ║   Spotify Web Manager                            ║${NC}"
    echo -e "${CYAN}${BOLD}  ║   Raspberry Pi 4 — Pi OS Trixie  v${SCRIPT_VERSION}          ║${NC}"
    echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════════════╣${NC}"
    printf  "${CYAN}${BOLD}  ║${NC}  Spotify Web  : ${colour}%-10s${NC}                        ${CYAN}${BOLD}║${NC}\n" "$status"
    echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}                                                  ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}    ${BOLD}1)${NC}  Install / Reinstall                       ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}    ${BOLD}2)${NC}  Uninstall                                 ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}    ${BOLD}3)${NC}  Exit                                      ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}                                                  ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

main() {
    while true; do
        show_menu
        read -rp "  Enter choice [1-3]: " choice
        case "$choice" in
            1) install_shortcut;  echo ""; read -rp "  Press [Enter] to continue…" _ ;;
            2) uninstall_shortcut; echo ""; read -rp "  Press [Enter] to continue…" _ ;;
            3) exit 0 ;;
            *) echo -e "  ${RED}Invalid option.${NC}"; sleep 1 ;;
        esac
    done
}

main
