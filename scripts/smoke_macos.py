#!/usr/bin/env python3
"""Open the Mac download as a TD would, and wait for its window.

Unzips the release zip with ditto (as Finder does), checks what the Mac checks
before running an app (an intact signature) and what the download promises
(its version, both Apple Silicon and Intel, no App Sandbox, the .meow file
type), then starts the app with a disposable library and waits for its window.
It quits the app the way Quit in the Dock does and requires a clean exit. Only
the process started here is stopped.

Needs macOS and pyobjc-framework-Quartz (which brings AppKit).

    python scripts/smoke_macos.py meow-chess-v1.6.0-macos.zip --expected-version 1.6.0
"""
import argparse
import os
import plistlib
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def bundle_issues(app, expected_version):
    issues = []
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version = info.get('CFBundleShortVersionString')
    if expected_version and version != expected_version:
        issues.append(f'version {version!r}, expected {expected_version!r}')

    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    archs = subprocess.run(['lipo', '-archs', str(executable)],
                           capture_output=True, text=True, check=True).stdout.split()
    for arch in ('arm64', 'x86_64'):
        if arch not in archs:
            issues.append(f'no {arch} code ({" ".join(archs)}), so some Macs cannot run it')

    # A broken signature is what makes a Mac call a download "damaged"; an ad
    # hoc one only makes it ask once (docs/USING.md).
    verify = subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)],
                            capture_output=True, text=True)
    if verify.returncode != 0:
        issues.append(f'signature does not verify:\n{verify.stderr.strip()}')

    shown = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(app)],
                           capture_output=True)
    entitlements = plistlib.loads(shown.stdout) if shown.stdout.strip() else {}
    if entitlements.get('com.apple.security.app-sandbox'):
        issues.append('signed with the App Sandbox on, which CI cannot test (scripts/lint.py)')

    extensions = {
        extension
        for declared in info.get('UTExportedTypeDeclarations', [])
        for extension in declared.get('UTTypeTagSpecification', {}).get('public.filename-extension', [])
    }
    if 'meow' not in extensions:
        issues.append('does not declare the .meow file type, so double-clicking an event will not open it')
    return issues, executable


def has_window(pid):
    from Quartz import (CGWindowListCopyWindowInfo, kCGNullWindowID, kCGWindowLayer,
                        kCGWindowListOptionOnScreenOnly, kCGWindowOwnerPID)
    windows = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID) or []
    # Layer 0 is ordinary windows; menu bar items and the like sit above it.
    return any(w.get(kCGWindowOwnerPID) == pid and w.get(kCGWindowLayer, 0) == 0 for w in windows)


def quit_app(pid):
    from AppKit import NSRunningApplication
    running = NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
    return running is not None and running.terminate()


def open_and_quit(executable, data_dir):
    app = subprocess.Popen([str(executable)], env={**os.environ, 'MEOW_DATA_DIR': str(data_dir)})
    try:
        deadline = time.monotonic() + 30
        while not has_window(app.pid):
            if app.poll() is not None:
                if app.returncode == -9:
                    return ('the Mac killed the app as it started, which it does to an ad hoc '
                            'signed app that claims an entitlement needing a developer account')
                return f'the app exited before opening a window: {app.returncode}'
            if time.monotonic() > deadline:
                return 'the app did not open a window within 30 seconds'
            time.sleep(0.25)
        time.sleep(3)
        if app.poll() is not None:
            return f'the app exited during startup: {app.returncode}'
        if not quit_app(app.pid):
            return 'the app refused a normal quit'
        try:
            code = app.wait(10)
        except subprocess.TimeoutExpired:
            return 'the app did not quit within 10 seconds'
        if code != 0:
            return f'the app quit with exit code {code}'
        return None
    finally:
        if app.poll() is None:
            app.kill()
            app.wait(10)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('zip', type=Path)
    parser.add_argument('--expected-version')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        raise SystemExit('This opens the Mac app, so it runs only on a Mac.')

    with tempfile.TemporaryDirectory(prefix='meow-smoke-') as temp:
        work = Path(temp)
        subprocess.run(['ditto', '-x', '-k', str(args.zip), str(work / 'unzipped')], check=True)
        apps = sorted((work / 'unzipped').glob('*.app'))
        if len(apps) != 1:
            raise SystemExit(f'FAIL: the zip holds {len(apps)} apps at its top level, expected one')
        issues, executable = bundle_issues(apps[0], args.expected_version)
        if issues:
            raise SystemExit('FAIL: ' + '\nFAIL: '.join(issues))
        library = work / 'library'
        library.mkdir()
        problem = open_and_quit(executable, library)
        if problem:
            raise SystemExit(f'FAIL: {problem}')
    print(f'PASS: {apps[0].name} from {args.zip.name} opened its window and quit normally.')


if __name__ == '__main__':
    main()
