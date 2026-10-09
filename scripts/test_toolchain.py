#!/usr/bin/env python3
"""dart_executable must hand subprocess the real dart.exe on Windows."""
from pathlib import Path
import tempfile
import unittest

from toolchain import dart_executable


class DartExecutableTest(unittest.TestCase):
    def test_windows_bat_wrapper_resolves_to_the_sdk_exe(self):
        with tempfile.TemporaryDirectory() as temp:
            bin_dir = Path(temp) / 'flutter' / 'bin'
            exe = bin_dir / 'cache/dart-sdk/bin/dart.exe'
            exe.parent.mkdir(parents=True)
            exe.write_bytes(b'')
            found = dart_executable(lambda _: str(bin_dir / 'dart.bat'), windows=True)
            self.assertEqual(Path(found), exe)

    def test_windows_upper_case_suffix_is_lowered(self):
        with tempfile.TemporaryDirectory() as temp:
            exe = Path(temp) / 'dart.exe'
            exe.write_bytes(b'')
            found = dart_executable(lambda _: str(Path(temp) / 'dart.EXE'), windows=True)
            # PATHEXT casing; Dart's hooks need the lower-case suffix.
            self.assertEqual(Path(found), exe)

    def test_posix_path_is_used_unchanged(self):
        with tempfile.TemporaryDirectory() as temp:
            exe = Path(temp) / 'dart'
            exe.write_bytes(b'')
            self.assertEqual(dart_executable(lambda _: str(exe), windows=False), str(exe))

    def test_missing_dart_fails_loudly(self):
        with self.assertRaisesRegex(RuntimeError, 'PATH'):
            dart_executable(lambda _: None, windows=False)
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(RuntimeError, 'missing'):
                dart_executable(lambda _: str(Path(temp) / 'dart.bat'), windows=True)


if __name__ == '__main__':
    unittest.main()
