#!/usr/bin/env python3
"""The launcher's Exec line must survive Desktop Entry unquoting for any path."""
import os
from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest import mock

import install_linux_launcher
from install_linux_launcher import exec_argument


def desktop_unquote(value):
    """An independent reading of the Desktop Entry spec, as a launcher parses Exec."""
    # 1. String-value escapes.
    value = re.sub(r'\\(.)', lambda m: {'s': ' ', 'n': '\n', 't': '\t', 'r': '\r'}.get(m[1], m[1]), value)
    # 2. One quoted argument: \" \` \$ \\ inside double quotes, then %% field codes.
    if not (value.startswith('"') and value.endswith('"')):
        raise ValueError(f'not quoted: {value}')
    out, body, i = [], value[1:-1], 0
    while i < len(body):
        if body[i] == '\\':
            if i + 1 >= len(body) or body[i + 1] not in '"`$\\':
                raise ValueError(f'invalid escape in {value}')
            out.append(body[i + 1])
            i += 2
        elif body[i] in '"`$':
            raise ValueError(f'unescaped reserved character in {value}')
        else:
            out.append(body[i])
            i += 1
    return ''.join(out).replace('%%', '%')


class ExecArgumentTest(unittest.TestCase):
    def test_reserved_characters_round_trip(self):
        for path in ['/opt/meow/meow_chess', '/home/a b/meow chess/meow_chess',
                     '/x/$HOME/`id`/meow', '/x/back\\slash/"quote"/meow', '/x/100%/%f/meow',
                     "/x/it's/meow", '/x/café/meow']:
            with self.subTest(path=path):
                self.assertEqual(desktop_unquote(exec_argument(path)), path)

    def test_characters_exec_cannot_carry_are_refused(self):
        for path in ['/x/new\nline', '/x/tab\there', '/x/a=b', '/x/cr\r']:
            with self.subTest(path=path), self.assertRaises(ValueError):
                exec_argument(path)


class InstallTest(unittest.TestCase):
    def test_installs_entry_and_icon_into_xdg_data_home(self):
        with tempfile.TemporaryDirectory() as temp:
            bundle = Path(temp) / 'bundle dir $x'
            icon = bundle / 'data/flutter_assets/assets/icon/meow_chess.png'
            icon.parent.mkdir(parents=True)
            icon.write_bytes(b'png')
            executable = bundle / 'meow_chess'
            executable.write_text('#!/bin/sh\n')
            executable.chmod(0o755)
            data = Path(temp) / 'data'
            # No desktop cache tools: nothing outside the temporary tree runs.
            with mock.patch.dict(os.environ, {'XDG_DATA_HOME': str(data)}), \
                    mock.patch.object(sys, 'argv', ['install', '--bundle', str(bundle)]), \
                    mock.patch.object(install_linux_launcher.shutil, 'which', return_value=None), \
                    mock.patch('builtins.print'):
                install_linux_launcher.main()
            entry = data / 'applications/org.meowchess.meow_chess.desktop'
            exec_lines = [l for l in entry.read_text().splitlines() if l.startswith('Exec=')]
            self.assertEqual(len(exec_lines), 1)
            argument, field = exec_lines[0].removeprefix('Exec=').rsplit(' ', 1)
            self.assertEqual(field, '%f')
            self.assertEqual(desktop_unquote(argument), str(executable.resolve()))
            self.assertEqual((data / 'icons/hicolor/256x256/apps/org.meowchess.meow_chess.png').read_bytes(), b'png')


if __name__ == '__main__':
    unittest.main()
