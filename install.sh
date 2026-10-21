#!/bin/sh
# Adds Backdrop to your app menu (desktop entry + icon) for the current user, pointing at this
# folder, wherever it was cloned. Run it again after moving the folder.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

install -Dm644 "$HERE/data/goldengate-backdrop.svg" \
    "$DATA/icons/hicolor/scalable/apps/goldengate-backdrop.svg"
mkdir -p "$DATA/applications"
sed "s|^Exec=.*|Exec=$HERE/backdrop|" "$HERE/data/goldengate-wallpaper.desktop" \
    > "$DATA/applications/goldengate-wallpaper.desktop"
chmod +x "$HERE/backdrop"

# refresh the icon and app menu caches when the tools are there
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t "$DATA/icons/hicolor" >/dev/null 2>&1 || true
command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || true

echo "Backdrop is in your app menu now (or run: $HERE/backdrop)"
