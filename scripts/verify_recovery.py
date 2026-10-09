#!/usr/bin/env python3
"""Kill our disposable Dart writer after ACK; verify WAL recovery on Linux/Windows."""
import json
import os
from pathlib import Path
import queue
import signal
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time

from toolchain import dart_executable


class RecoveryCheckError(Exception):
    """The recovered event does not match what the writer acknowledged."""


def check(condition, *detail):
    # Not assert: python -O would strip every recovery check and print PASS.
    if not condition:
        raise RecoveryCheckError(*detail or ('check failed',))


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
                        _, revision_text, writer_text = line.split()
                        acknowledged = int(revision_text)
                        writer_pid = int(writer_text)
                        check(writer_pid > 0, line)
                        if acknowledged == 5:
                            check(Path(f'{event}-wal').stat().st_size > 0, 'No WAL before the kill')
                            # Kill the helper identified through our own pipe,
                            # even if this SDK launches it beneath a CLI parent.
                            os.kill(writer_pid, signal.SIGTERM if os.name == 'nt' else signal.SIGKILL)
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
            check(acknowledged == 5, f'Writer did not acknowledge five commits: {errors.read()}')
            # TerminateProcess on Windows returns a positive exit code.
            check(process.returncode != 0, 'Expected abrupt termination, not graceful closure')
        check(Path(f'{event}-wal').stat().st_size > 0, 'Writer must not close/checkpoint cleanly')
        connection = sqlite3.connect(event)
        try:
            check(connection.execute('PRAGMA integrity_check').fetchone()[0] == 'ok', 'integrity_check')
            check(connection.execute('PRAGMA foreign_key_check').fetchall() == [], 'foreign_key_check')
            revision, data = connection.execute('SELECT revision,data FROM event').fetchone()
            check(revision == acknowledged, (revision, acknowledged))
            check(json.loads(data)['name'] == f'Revision {revision}', 'Event name')
            players = connection.execute('SELECT data FROM player').fetchall()
            check(len(players) == 120, ('Players', len(players)))
            check(all(json.loads(row[0])['name'].endswith(f'revision {revision}') for row in players), 'Player revision')
            check(connection.execute('SELECT MAX(revision) FROM audit').fetchone()[0] == revision, 'Audit')
            check(connection.execute('SELECT COUNT(*) FROM audit').fetchone()[0] == revision, 'Audit')
            check(connection.execute('SELECT COUNT(*) FROM node').fetchone()[0] == revision, 'Nodes')
        finally:
            # sqlite3's context manager commits but does not close; Windows
            # cannot remove the temporary directory while the handle is open.
            connection.close()
        print(f'PASS: abrupt termination recovered revision {revision}, 120 entrants and matching history.')


if __name__ == '__main__':
    try:
        verify()
    except RecoveryCheckError as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
