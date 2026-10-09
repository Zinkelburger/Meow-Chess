#!/usr/bin/env bash
# Packages the built Linux bundle as a .deb for Debian, Ubuntu, Mint and kin.
#
#   packaging/deb/build_deb.sh <version> [bundle-dir] [output-dir]
#
# Run after `flutter build linux --release`. Layout: packaging/stage_linux.sh.
set -euo pipefail

VERSION="${1:?usage: build_deb.sh <version> [bundle-dir] [output-dir]}"
VERSION="${VERSION#v}"
BUNDLE="${2:-build/linux/x64/release/bundle}"
OUT="${3:-dist}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# A dash would split 1.2.0-rc1 into upstream 1.2.0 and Debian revision rc1,
# which dpkg orders *after* 1.2.0. 1.2.0~rc1 sorts before it, as in rpm.
DEB_VERSION="${VERSION//-/\~}"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
"$ROOT/packaging/stage_linux.sh" "$BUNDLE" "$STAGE"
install -d "$STAGE/DEBIAN"

# Ubuntu 24.04 renamed several libraries with a t64 suffix; accept either.
INSTALLED_KB="$(du -sk "$STAGE" | cut -f1)"
cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: meow-chess
Version: $DEB_VERSION
Section: games
Priority: optional
Architecture: amd64
Installed-Size: $INSTALLED_KB
Depends: libgtk-3-0t64 | libgtk-3-0, libglib2.0-0t64 | libglib2.0-0, libsecret-1-0, libjson-glib-1.0-0, libstdc++6
Maintainer: Andrew Bernal <andrewlbernal@gmail.com>
Homepage: https://github.com/Zinkelburger/Meow-Chess
Description: Run Swiss and quad chess tournaments
 An offline tournament director workspace. Each event is saved as a .meow
 file on your computer and works without internet.
CONTROL

mkdir -p "$OUT"
dpkg-deb --build --root-owner-group "$STAGE" \
  "$OUT/meow-chess-$VERSION-linux-amd64.deb"
