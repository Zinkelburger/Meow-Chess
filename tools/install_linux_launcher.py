#!/usr/bin/env python3
"""Install a local app launcher and Wayland icon without changing file defaults."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess


def exec_argument(value: str) -> str:
    # Desktop Entry Exec has its own quoting rules; shell single quotes are
    # not valid here. The desktop parser removes one layer of backslashes.
    if any(character in value for character in '\n\r\t='):
        raise ValueError('Unsupported character in executable path')
    value = value.replace('%', '%%')
    value = ''.join('\\' + c if c in '\\"`$' else c for c in value)
    return '"' + value.replace('\\', '\\\\') + '"'


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--bundle', type=Path,
        default=root / 'build/linux/x64/release/bundle',
        help='Built Linux bundle; defaults to the release build',
    )
    args = parser.parse_args()
    bundle = args.bundle.resolve()
    executable = bundle / 'meow_chess'
    icon = bundle / 'data/flutter_assets/assets/icon/meow_chess.png'
    if not executable.is_file() or not os.access(executable, os.X_OK):
        parser.error(f'No executable at {executable}; build the app first')
    if not icon.is_file():
        parser.error(f'The bundle is missing its icon: {icon}')

    app_id = 'org.meowchess.meow_chess'
    data = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
    entry = data / 'applications' / f'{app_id}.desktop'
    icon_target = data / 'icons/hicolor/256x256/apps' / f'{app_id}.png'
    entry.parent.mkdir(parents=True, exist_ok=True)
    icon_target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(icon, icon_target)
    template = (root / 'linux' / f'{app_id}.desktop').read_text()
    entry.write_text(''.join(
        f'Exec={exec_argument(str(executable))} %f\n'
        if line.startswith('Exec=') else line
        for line in template.splitlines(keepends=True)
    ))
    entry.chmod(0o644)

    # Refresh launchers and icon lookup without restarting Plasma or the app.
    for command in [
        ['update-desktop-database', str(entry.parent)],
        ['gtk-update-icon-cache', '--force', '--ignore-theme-index',
         str(data / 'icons/hicolor')],
        ['kbuildsycoca6', '--noincremental'],
    ]:
        if shutil.which(command[0]):
            subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
    print(f'Installed launcher: {entry}')
    print(f'Installed Wayland icon: {icon_target}')


if __name__ == '__main__':
    main()
