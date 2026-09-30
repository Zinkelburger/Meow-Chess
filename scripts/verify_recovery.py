#!/usr/bin/env python3
"""Kill our disposable Dart writer after ACK; verify WAL recovery on Linux/Windows."""
import json
import os
from pathlib import Path
import queue
import shutil
import sqlite3
import subprocess
import tempfile
import threading
import time


def dart_executable():
    candidate = shutil.which('dart')
    if not candidate:
        raise RuntimeError('Dart must be on PATH')
    # Execute the SDK directly: no cmd.exe quoting or .bat shell on Windows.
    path = Path(candidate)
    if os.name == 'nt' and path.suffix.lower() in ('.bat', '.cmd'):
        path = path.parent / 'cache/dart-sdk/bin/dart.exe'
    if not path.is_file():
        raise RuntimeError(f'Dart executable missing: {path}')
    return str(path)


def verify():
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='meow crash é ') as directory:
        event = Path(directory) / 'synthetic event.meow'
        with tempfile.TemporaryFile(mode='w+', encoding='utf-8') as errors:
            process = subprocess.Popen(
                [dart_executable(), 'run', 'tools/recovery_fixture.dart', str(event)],
                cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=errors, text=True, encoding='utf-8',
            )
            lines = queue.Queue()

            def read_lines():
                # select()/selectors cannot wait on anonymous pipes on Windows.
                for line in process.stdout:
                    lines.put(line)
                lines.put(None)

            reader = threading.Thread(target=read_lines, daemon=True)
            reader.start()
            acknowledged = 0
            try:
                deadline = time.monotonic() + 120
                while time.monotonic() < deadline:
                    try:
                        line = lines.get(timeout=min(1, max(.01, deadline - time.monotonic())))
                    except queue.Empty:
                        continue
                    if line is None:
                        break
                    if line.startswith('ACK '):
                        acknowledged = int(line.split()[1])
                        if acknowledged == 5:
                            assert Path(f'{event}-wal').stat().st_size > 0
                            process.kill()
                            break
                        process.stdin.write('NEXT\n')
                        process.stdin.flush()
            finally:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=15)
                process.stdin.close()
                reader.join(timeout=5)
                process.stdout.close()
            errors.seek(0)
            assert acknowledged == 5, f'Writer did not acknowledge five commits: {errors.read()}'
            # TerminateProcess on Windows returns a positive exit code.
            assert process.returncode != 0, 'Expected abrupt termination, not graceful closure'
        connection = sqlite3.connect(event)
        try:
            assert connection.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
            assert connection.execute('PRAGMA foreign_key_check').fetchall() == []
            revision, data = connection.execute('SELECT revision,data FROM event').fetchone()
            assert revision == acknowledged, (revision, acknowledged)
            assert json.loads(data)['name'] == f'Revision {revision}'
            players = connection.execute('SELECT data FROM player').fetchall()
            assert len(players) == 120
            assert all(json.loads(row[0])['name'].endswith(f'revision {revision}') for row in players)
            assert connection.execute('SELECT MAX(revision) FROM audit').fetchone()[0] == revision
            assert connection.execute('SELECT COUNT(*) FROM audit').fetchone()[0] == revision
            assert connection.execute('SELECT COUNT(*) FROM node').fetchone()[0] == revision
        finally:
            # sqlite3's context manager commits but does not close; Windows
            # cannot remove the temporary directory while the handle is open.
            connection.close()
        print(f'PASS: abrupt termination recovered revision {revision}, 120 entrants and matching history.')


if __name__ == '__main__':
    verify()
