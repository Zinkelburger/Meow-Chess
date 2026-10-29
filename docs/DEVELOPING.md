# Developing

## Build and run

With Flutter installed, run `flutter pub get`, then `flutter run -d linux` (or
`-d windows` / `-d macos` on the corresponding host). `flutter test` runs the
unit and widget tests; `flutter analyze lib test integration_test tools
scripts` and `python3 scripts/lint.py` are the other two checks CI runs first.

On the maintainer's Linux workstation, `scripts/ci.sh` wraps the same commands
in a bounded job runner shared with Chess Auto Prep: `scripts/ci.sh test`,
`analyze`, `lint`, `integration`, `recovery`, `exports` and `build` (a Linux
release build, whose executable is `build/linux/x64/release/bundle/meow_chess`).
Other machines can set `MEOW_JOB_RUNNER` or use the plain Flutter commands.

A filename argument opens that event; in release builds a second launch hands
its file to the window already open. `MEOW_DATA_DIR` overrides the recent-event
library location for isolated testing.

## The CI gate

Every push to `main` runs [ci.yml](../.github/workflows/ci.yml): analysis,
lint, all tests, independent DBF decoding, abrupt-termination recovery and the
native desktop integration tests on Ubuntu 22.04, Windows Server 2022 and
Windows Server 2025, plus a macOS job for file publication and bookmarks.
[Release qualification](TESTING.md) describes each job and the manual checks
that remain. All work lands on `main`; the project does not use feature
branches.

## Releasing

A release is one commit that bumps the version in `pubspec.yaml`,
`lib/version.dart` and the Flatpak metainfo, adds the entry to
[the changelog](CHANGELOG.md) and updates the README, followed by a tag:

```
git tag v1.3.1 && git push origin main v1.3.1
```

The lint refuses a tag that does not match the package version. Pushing the
tag runs [release.yml](../.github/workflows/release.yml): the CI gate, then a
GitHub Release with a Windows setup `.exe` and portable zip, and Linux `.deb`,
`.rpm`, `.flatpak` and portable zip, plus checksums. A tag with a dash
(`v1.3.1-rc1`) is published as a pre-release. The Windows build alone can be
tried from Actions → Windows build → Run workflow.

## The browser version

`python3 scripts/build_web.py` builds the browser version into `build/web`.
The website is a static copy: after a release, or any change a TD would notice,
sync it with `python3 scripts/build_web.py --site ../Chess-Auto-Prep` and
commit in that repository. https://chessautoprep.com/meow-chess/meow-build.json
names the commit the live copy was built from. [The browser version](WEB.md)
explains what differs there and how the site's fetch function works.

## Desktop integration

Every package makes `.meow` files open in Meow Chess on double-click. The
portable zips do it on first launch instead: the app asks "Set up Meow Chess on
this computer?" and, on Linux, installs a menu entry, icon and the `.meow` file
type under `~/.local/share`; on Windows, it registers `.meow` for the current
user. Nothing needs administrator rights. Debug builds never ask.
`MEOW_CHESS_DESKTOP_SETUP=1` sets up without asking and `=0` never asks, for
scripted installs.

The icon is [meow_chess_master.png](../assets/icon/meow_chess_master.png);
`tools/make_icons.sh` regenerates every platform size from it. The logo appears
on the welcome screen and as the desktop app icon. Window controls, movement and
resizing use the operating system's standard decorations; whether an icon
appears in the title bar depends on the desktop environment.

For a local checkout on KDE/Wayland, build the app and run
`python3 tools/install_linux_launcher.py`. This installs the menu entry and
icon whose name matches the Wayland app ID, without changing default file
handlers. Use `--bundle build/linux/x64/debug/bundle` to point the launcher at a
debug build. Rerun after changing the logo or moving the checkout; reopen the
app if Plasma still shows a cached icon. Packaged installations already include
this entry.

## Automation

The MCP server in `scripts/tournament_mcp.dart` drives an event from an
assistant; see [tournament automation](TOURNAMENT_AUTOMATION.md).
