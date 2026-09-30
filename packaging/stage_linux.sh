#!/usr/bin/env bash
# Lays out the built Linux bundle the way the .deb and .rpm install it:
#
#   /opt/meow-chess/                     the Flutter bundle, untouched
#   /usr/bin/meow_chess                  symlink, so Exec=meow_chess %f works
#   /usr/share/applications/             desktop entry (menu + .meow handler)
#   /usr/share/mime/packages/            the .meow MIME type
#   /usr/share/icons/hicolor/256x256/    app and .meow file icon
#   /usr/share/metainfo/                 what software centres show
#
#   packaging/stage_linux.sh <bundle-dir> <stage-dir>
#
# The package managers' own triggers refresh the desktop, MIME and icon caches
# for these directories, so neither package needs install scripts. With the
# entry installed system-wide the app never shows its own setup offer.
set -euo pipefail

BUNDLE="${1:?usage: stage_linux.sh <bundle-dir> <stage-dir>}"
STAGE="${2:?usage: stage_linux.sh <bundle-dir> <stage-dir>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID=org.meowchess.meow_chess

test -x "$BUNDLE/meow_chess" || {
  echo "no bundle at $BUNDLE — run flutter build linux --release first" >&2
  exit 1
}

install -d \
  "$STAGE/opt/meow-chess" \
  "$STAGE/usr/bin" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/mime/packages" \
  "$STAGE/usr/share/icons/hicolor/256x256/apps" \
  "$STAGE/usr/share/metainfo"

cp -a "$BUNDLE"/. "$STAGE/opt/meow-chess/"
ln -s /opt/meow-chess/meow_chess "$STAGE/usr/bin/meow_chess"
install -m644 "$ROOT/linux/$APP_ID.desktop" "$STAGE/usr/share/applications/"
install -m644 "$ROOT/linux/$APP_ID.xml" "$STAGE/usr/share/mime/packages/"
install -m644 "$ROOT/assets/icon/meow_chess.png" \
  "$STAGE/usr/share/icons/hicolor/256x256/apps/$APP_ID.png"
install -m644 "$ROOT/packaging/flatpak/$APP_ID.metainfo.xml" \
  "$STAGE/usr/share/metainfo/"
