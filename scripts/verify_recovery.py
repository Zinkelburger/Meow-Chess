#!/usr/bin/env python3
"""Kill our disposable Dart writer and verify the event file on Linux/Windows.

Two scenarios:

* Idle kill. The writer is killed while waiting between saves. Every save
  empties the recovery file (the WAL), so the event file alone must hold the
  last acknowledged save. An earlier copy is then restored over the event file
  beside the recovery file the killed writer left, as a director does after a
  crash, and must open as itself: nothing may be left to replay over it.
* Mid-save kill. The writer saves without pausing and is killed at whatever
  point it has reached, repeatedly. Reopening must recover at least every
  acknowledged save, with the event, its players, the audit trail and the
  history all at the same revision. When the kill lands between a commit and
  its checkpoint, this is SQLite replaying the recovery file.
"""
import json
import os
from pathlib import Path
import queue
import random
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time

from toolchain import dart_executable

ENTRANTS = 120
MID_SAVE_RUNS = 6


class RecoveryCheckError(Exception):
    """The recovered event does not match what the writer acknowledged."""


def check(condition, *detail):
    # Not assert: python -O would strip every recovery check and print PASS.
    if not condition:
        raise RecoveryCheckError(*detail or ('check failed',))


def kill(pid):
    os.kill(pid, signal.SIGTERM if os.name == 'nt' else signal.SIGKILL)


def drive(root, event, on_ack, continuous=False):
    """Runs the writer on [event]; [on_ack](revision, pid) returns True to stop.

    Returns the last acknowledged revision once the writer has been killed.
    """
    arguments = [dart_executable(), 'run', 'tools/recovery_fixture.dart', str(event)]
    if continuous:
        arguments.append('--continuous')
    with tempfile.TemporaryFile(mode='w+', encoding='utf-8') as errors:
        process = subprocess.Popen(
            arguments, cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
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
        stopped = False
        try:
            deadline = time.monotonic() + 180
            while time.monotonic() < deadline:
                try:
                    line = lines.get(timeout=min(1, max(.01, deadline - time.monotonic())))
                except queue.Empty:
                    continue
                if line is None:
                    break
                if not line.startswith('ACK '):
                    continue
                _, revision_text, writer_text = line.split()
                revision, writer_pid = int(revision_text), int(writer_text)
                check(writer_pid > 0, line)
                check(revision == acknowledged + 1, ('Acknowledgements out of order', acknowledged, revision))
                acknowledged = revision
                if on_ack(revision, writer_pid):
                    # Kill the helper identified through our own pipe, even if
                    # this SDK launches it beneath a CLI parent.
                    kill(writer_pid)
                    stopped = True
                    break
                if not continuous:
                    process.stdin.write('NEXT\n')
                    process.stdin.flush()
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=15)
            try:
                process.stdin.close()
            except OSError:
                pass  # The killed writer's end of the pipe is already gone.
            reader.join(timeout=5)
            process.stdout.close()
        errors.seek(0)
        check(stopped, f'Writer stopped before it was killed at revision {acknowledged}: {errors.read()}')
        # TerminateProcess on Windows returns a positive exit code.
        check(process.returncode != 0, 'Expected abrupt termination, not graceful closure')
    return acknowledged


def check_consistent(path, at_least, label):
    """The event at [path] is intact and wholly at one revision >= [at_least]."""
    connection = sqlite3.connect(path)
    try:
        check(connection.execute('PRAGMA integrity_check').fetchone()[0] == 'ok', label, 'integrity_check')
        check(connection.execute('PRAGMA foreign_key_check').fetchall() == [], label, 'foreign_key_check')
        revision, data = connection.execute('SELECT revision,data FROM event').fetchone()
        check(revision >= at_least, label, ('Lost an acknowledged save', revision, at_least))
        check(json.loads(data)['name'] == f'Revision {revision}', label, 'Event name')
        players = connection.execute('SELECT data FROM player').fetchall()
        check(len(players) == ENTRANTS, label, ('Players', len(players)))
        check(all(json.loads(row[0])['name'].endswith(f'revision {revision}') for row in players),
              label, 'Players from another revision')
        check(connection.execute('SELECT MAX(revision) FROM audit').fetchone()[0] == revision, label, 'Audit')
        check(connection.execute('SELECT COUNT(*) FROM audit').fetchone()[0] == revision, label, 'Audit count')
        check(connection.execute('SELECT COUNT(*) FROM node').fetchone()[0] == revision, label, 'Nodes')
        return revision
    finally:
        # sqlite3's context manager commits but does not close; Windows
        # cannot remove the temporary directory while the handle is open.
        connection.close()


def idle_kill(root, directory):
    event = Path(directory) / 'synthetic event.meow'
    earlier = Path(directory) / 'earlier copy.meow'

    def on_ack(revision, _):
        if revision == 3:
            # The writer is idle until NEXT, and every save empties the
            # recovery file, so the event file alone is the whole of revision 3.
            shutil.copyfile(event, earlier)
        if revision == 5:
            check(Path(f'{event}-wal').exists(), 'No recovery file before the kill')
            return True
        return False

    acknowledged = drive(root, event, on_ack)
    check(acknowledged == 5, ('Writer acknowledged', acknowledged))
    wal = Path(f'{event}-wal')
    check(wal.exists(), 'Writer must not close cleanly')
    check(wal.stat().st_size == 0, 'A committed save left pages in the recovery file')
    # The crash scene with the earlier copy put back under the event's name,
    # the leftover recovery file still beside it.
    restored = Path(directory) / 'restored'
    restored.mkdir()
    shutil.copyfile(wal, restored / f'{event.name}-wal')
    shutil.copyfile(earlier, restored / event.name)
    check(check_consistent(restored / event.name, 3, 'restored copy') == 3, 'Restored copy is not revision 3')
    check(check_consistent(event, acknowledged, 'idle kill') == acknowledged, 'Idle kill revision')
    return acknowledged


def mid_save_kill(root, directory, run):
    event = Path(directory) / f'mid save {run}.meow'
    # Far enough in that saves are steady, at a point that differs per run.
    target = random.randint(3, 40)

    def on_ack(revision, _):
        if revision < target:
            return False
        # Killing on the acknowledgement lands while the writer is between
        # saves; a pause of up to a few saves' length lands anywhere in one.
        time.sleep(random.uniform(0, .08))
        return True

    acknowledged = drive(root, event, on_ack, continuous=True)
    wal = Path(f'{event}-wal')
    replayed = wal.exists() and wal.stat().st_size > 0
    revision = check_consistent(event, acknowledged, f'mid-save run {run}')
    return acknowledged, revision, replayed


def verify():
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='meow crash é ') as directory:
        idle = idle_kill(root, directory)
        runs = [mid_save_kill(root, directory, run) for run in range(MID_SAVE_RUNS)]
    replays = sum(1 for _, _, replayed in runs if replayed)
    detail = ', '.join(f'ack {a} -> {r}' for a, r, _ in runs)
    print(f'PASS: idle kill kept revision {idle} with {ENTRANTS} entrants and matching history; '
          'an earlier copy restored beside the leftover recovery file opened intact. '
          f'Mid-save kills recovered every acknowledged save ({detail}; '
          f'{replays} of {len(runs)} left pages in the recovery file to replay).')


if __name__ == '__main__':
    try:
        verify()
    except RecoveryCheckError as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
