#!/usr/bin/env bash
#
# install_appimage.sh
# Makes an AppImage executable, moves it to a permanent home, and registers
# it with your desktop environment so it shows up in your app launcher
# with its proper name and icon — same end result as AppImageLauncher.
#
# Usage:
#   ./install_appimage.sh ~/Downloads/SomeApp.AppImage
#
# What it does:
#   1. chmod +x the AppImage
#   2. Moves it to ~/Applications (created if missing — AppImages must live
#      somewhere permanent, since the .desktop entry points at a fixed path)
#   3. Extracts the bundled .desktop file + icon (every well-formed AppImage
#      ships these internally)
#   4. Patches Exec=/Icon= to point at the installed locations
#   5. Installs both into ~/.local/share/applications and ~/.local/share/icons
#   6. Refreshes the desktop database so the entry appears immediately

set -euo pipefail

APP_DIR="$HOME/Applications"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/appimages"

clean_orphans() {
    mkdir -p "$APP_DIR" "$DESKTOP_DIR" "$ICON_DIR"

    local orphan_desktops=()
    local referenced_icons=()

    for desktop_file in "$DESKTOP_DIR"/*.desktop; do
        [[ -e "$desktop_file" ]] || continue

        exec_line="$(grep -m1 '^Exec=' "$desktop_file" 2>/dev/null | cut -d= -f2- || true)"
        # Only consider entries this script manages (point into ~/Applications)
        [[ "$exec_line" == *"$APP_DIR"* ]] || continue

        # Exec line looks like: "/home/user/Applications/App.AppImage" %U
        app_path="$(echo "$exec_line" | sed -E 's/^"?([^"]+)"?.*/\1/')"

        if [[ ! -f "$app_path" ]]; then
            orphan_desktops+=("$desktop_file  (missing target: $app_path)")
        else
            icon_line="$(grep -m1 '^Icon=' "$desktop_file" 2>/dev/null | cut -d= -f2- || true)"
            [[ -n "$icon_line" ]] && referenced_icons+=("$icon_line")
        fi
    done

    local orphan_icons=()
    for icon_file in "$ICON_DIR"/*; do
        [[ -e "$icon_file" ]] || continue
        local found=0
        for ref in ${referenced_icons[@]+"${referenced_icons[@]}"}; do
            [[ "$ref" == "$icon_file" ]] && { found=1; break; }
        done
        [[ "$found" -eq 0 ]] && orphan_icons+=("$icon_file")
    done

    if [[ ${#orphan_desktops[@]} -eq 0 && ${#orphan_icons[@]} -eq 0 ]]; then
        echo "No orphaned entries found. Everything's clean."
        exit 0
    fi

    if [[ ${#orphan_desktops[@]} -gt 0 ]]; then
        echo "── Orphaned launcher entries (AppImage no longer exists) ──"
        printf '  %s\n' "${orphan_desktops[@]}"
        echo
    fi

    if [[ ${#orphan_icons[@]} -gt 0 ]]; then
        echo "── Orphaned icons (not referenced by any valid entry) ──"
        printf '  %s\n' "${orphan_icons[@]}"
        echo
    fi

    read -r -p "Delete all of the above? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        for entry in ${orphan_desktops[@]+"${orphan_desktops[@]}"}; do
            rm -f "${entry%%  (missing target:*}"
        done
        for icon in ${orphan_icons[@]+"${orphan_icons[@]}"}; do
            rm -f "$icon"
        done
        echo "Cleaned up."
    else
        echo "Skipped — nothing deleted."
    fi
    exit 0
}

if [[ "${1:-}" == "--clean" ]]; then
    clean_orphans
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/App.AppImage"
    echo "       $0 --clean    (scan for and remove orphaned launcher entries/icons)"
    exit 1
fi

SRC="$1"

if [[ ! -f "$SRC" ]]; then
    echo "Error: file not found: $SRC"
    exit 1
fi

if [[ "$SRC" != *.AppImage && "$SRC" != *.appimage ]]; then
    echo "Warning: '$SRC' doesn't end in .AppImage — continuing anyway."
fi

mkdir -p "$APP_DIR" "$DESKTOP_DIR" "$ICON_DIR"

BASENAME="$(basename "$SRC")"
DEST="$APP_DIR/$BASENAME"

chmod +x "$SRC"

# Move into the permanent location (skip if already installed there)
if [[ "$SRC" != "$DEST" ]]; then
    mv -n "$SRC" "$DEST"
fi
chmod +x "$DEST"

echo "Installed AppImage to: $DEST"

# Extract the bundled .desktop file and icon
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

pushd "$WORKDIR" > /dev/null
"$DEST" --appimage-extract > /dev/null 2>&1 || {
    echo "Error: failed to extract AppImage contents. Some AppImages don't support --appimage-extract."
    exit 1
}
popd > /dev/null

EXTRACT_ROOT="$WORKDIR/squashfs-root"

DESKTOP_SRC="$(find "$EXTRACT_ROOT" -maxdepth 1 -name "*.desktop" | head -n1)"
if [[ -z "$DESKTOP_SRC" ]]; then
    echo "Error: no .desktop file found inside the AppImage — cannot register it automatically."
    exit 1
fi

APP_NAME="$(grep -m1 '^Name=' "$DESKTOP_SRC" | cut -d= -f2-)"
[[ -z "$APP_NAME" ]] && APP_NAME="${BASENAME%.*}"

ICON_NAME="$(grep -m1 '^Icon=' "$DESKTOP_SRC" | cut -d= -f2-)"

# Find the actual icon file (could be .png, .svg, .xpm, with or without extension in the desktop entry)
ICON_SRC=""
if [[ -n "$ICON_NAME" ]]; then
    ICON_SRC="$(find "$EXTRACT_ROOT" -maxdepth 2 \( -iname "${ICON_NAME}.png" -o -iname "${ICON_NAME}.svg" -o -iname "${ICON_NAME}.xpm" -o -iname "${ICON_NAME}" \) | head -n1)"
fi

SLUG="$(echo "$APP_NAME" | tr ' ' '_' | tr -dc '[:alnum:]_-')"
DESKTOP_DEST="$DESKTOP_DIR/${SLUG}.desktop"

if [[ -n "$ICON_SRC" ]]; then
    ICON_EXT="${ICON_SRC##*.}"
    ICON_DEST="$ICON_DIR/${SLUG}.${ICON_EXT}"
    cp "$ICON_SRC" "$ICON_DEST"
    echo "Installed icon to: $ICON_DEST"
else
    ICON_DEST=""
    echo "Warning: no icon found inside the AppImage — entry will use a generic icon."
fi

# Build the final .desktop file: copy original, then patch Exec/Icon lines
cp "$DESKTOP_SRC" "$DESKTOP_DEST"
sed -i "s|^Exec=.*|Exec=\"$DEST\" %U|" "$DESKTOP_DEST"
if [[ -n "$ICON_DEST" ]]; then
    sed -i "s|^Icon=.*|Icon=$ICON_DEST|" "$DESKTOP_DEST"
fi
chmod +x "$DESKTOP_DEST"

echo "Registered app: $APP_NAME"
echo "Desktop entry:  $DESKTOP_DEST"

# Refresh desktop launcher caches. Different DEs use different tools, and not
# all of them are installed on every system, so just try whichever exist —
# harmless to skip ones that aren't present.
REFRESHED=0

if command -v update-desktop-database > /dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" > /dev/null 2>&1 && REFRESHED=1
fi

if command -v kbuildsycoca6 > /dev/null 2>&1; then
    kbuildsycoca6 --noincremental > /dev/null 2>&1 && REFRESHED=1
elif command -v kbuildsycoca5 > /dev/null 2>&1; then
    kbuildsycoca5 --noincremental > /dev/null 2>&1 && REFRESHED=1
fi

if [[ "$REFRESHED" -eq 0 ]]; then
    echo "Note: no known cache-refresh tool found — the entry should still appear, possibly with a short delay."
fi

echo "Done. '$APP_NAME' should now appear in your application launcher."