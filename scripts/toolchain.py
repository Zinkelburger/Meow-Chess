"""Locate SDK executables so subprocess can run them on Linux, macOS and Windows."""
import os
from pathlib import Path
import shutil


def dart_executable(which=shutil.which, windows=None):
    """The Dart executable itself, never a .bat/.cmd wrapper.

    `which` and `windows` are seams for tests; callers pass neither.
    """
    windows = os.name == 'nt' if windows is None else windows
    candidate = which('dart')
    if not candidate:
        raise RuntimeError('Dart must be on PATH')
    # Execute the SDK directly: no cmd.exe quoting or .bat shell on Windows.
    path = Path(candidate)
    if windows and path.suffix.lower() in ('.bat', '.cmd'):
        path = path.parent / 'cache/dart-sdk/bin/dart.exe'
    # shutil.which uses PATHEXT casing (often .EXE). Dart's native hooks
    # detect the suffix case-sensitively and otherwise append a second .exe.
    if windows and path.suffix.lower() == '.exe':
        path = path.with_suffix('.exe')
    if not path.is_file():
        raise RuntimeError(f'Dart executable missing: {path}')
    return str(path)
