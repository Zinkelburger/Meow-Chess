#!/usr/bin/env bash
# Renders the transparent logo master into every icon the platforms need.
# Run after updating the master PNG; outputs are committed. Needs ImageMagick 7.
set -euo pipefail
cd "$(dirname "$0")/.."
source=assets/icon/meow_chess_master.png
render() {
  magick "$source" -resize "$1x$1" -background none -gravity center \
    -extent "$1x$1" -strip "$2"
}

# Linux window icon, desktop entry icon and packaging (one file for all).
render 256 assets/icon/meow_chess.png

# Windows executable icon: every size Explorer asks for.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for size in 16 24 32 48 64 128 256; do render "$size" "$tmp/$size.png"; done
magick "$tmp"/{16,24,32,48,64,128,256}.png windows/runner/resources/app_icon.ico

# macOS app icon set.
for size in 16 32 64 128 256 512 1024; do
  render "$size" "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png"
done
