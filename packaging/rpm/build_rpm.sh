#!/usr/bin/env bash
# Packages the built Linux bundle as an .rpm for Fedora, RHEL, openSUSE and kin.
#
#   packaging/rpm/build_rpm.sh <version> [bundle-dir] [output-dir]
#
# The counterpart of packaging/deb/build_deb.sh, with the same arguments and
# the same layout (packaging/stage_linux.sh). No %post scriptlets: Fedora's
# file triggers on the desktop, MIME and icon directories refresh the caches.
set -euo pipefail

VERSION="${1:?usage: build_rpm.sh <version> [bundle-dir] [output-dir]}"
VERSION="${VERSION#v}"
BUNDLE="${2:-build/linux/x64/release/bundle}"
OUT="${3:-dist}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_ID=org.meowchess.meow_chess

# RPM versions may not contain a dash; 1.2.0-rc1 becomes 1.2.0~rc1, which rpm
# also orders correctly (a ~suffix sorts *before* the release).
RPM_VERSION="${VERSION//-/\~}"

TOP="$(mktemp -d)"
trap 'rm -rf "$TOP"' EXIT
STAGE="$TOP/stage"
"$ROOT/packaging/stage_linux.sh" "$BUNDLE" "$STAGE"

# AutoReqProv is off on purpose: rpm would otherwise turn every library the
# bundle carries (pdfium, sqlite, the JNI shim's optional libjvm) into a
# Requires no repository provides. These are the real host dependencies,
# named by soname so they resolve on Fedora (gtk3, libsecret, ...) and
# openSUSE (libgtk-3-0, libsecret-1-0, ...) alike.
cat > "$TOP/meow-chess.spec" <<SPEC
%global debug_package %{nil}
%global __os_install_post %{nil}

Name:           meow-chess
Version:        $RPM_VERSION
Release:        1
Summary:        Run Swiss and quad chess tournaments
License:        AGPL-3.0-or-later
URL:            https://github.com/Zinkelburger/Meow-Chess
BuildArch:      x86_64
AutoReqProv:    no
Requires:       libgtk-3.so.0()(64bit)
Requires:       libglib-2.0.so.0()(64bit)
Requires:       libsecret-1.so.0()(64bit)
Requires:       libepoxy.so.0()(64bit)
Requires:       libfontconfig.so.1()(64bit)
Requires:       libstdc++.so.6()(64bit)

%description
An offline tournament director workspace. Each event is saved as a .meow
file on your computer and works without internet.

%install
cp -a $STAGE/. %{buildroot}/

%files
/opt/meow-chess
/usr/bin/meow_chess
/usr/share/applications/$APP_ID.desktop
/usr/share/mime/packages/$APP_ID.xml
/usr/share/icons/hicolor/256x256/apps/$APP_ID.png
/usr/share/metainfo/$APP_ID.metainfo.xml
SPEC

rpmbuild -bb \
  --define "_topdir $TOP" \
  --define "_rpmdir $TOP/RPMS" \
  --define "_build_id_links none" \
  "$TOP/meow-chess.spec"

mkdir -p "$OUT"
mv "$TOP/RPMS/x86_64/meow-chess-$RPM_VERSION-1.x86_64.rpm" \
   "$OUT/meow-chess-$VERSION-linux-x86_64.rpm"
