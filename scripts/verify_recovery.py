#!/usr/bin/env python3
"""Kill only our synthetic writer after an acknowledged commit; inspect its WAL recovery."""
import json
from pathlib import Path
import selectors
import sqlite3
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="meow-crash-") as directory:
    event = Path(directory) / "synthetic.meow"
    with tempfile.TemporaryFile(mode="w+") as errors:
        process = subprocess.Popen(
            ["dart", "run", "tools/recovery_fixture.dart", str(event)],
            cwd=root, stdout=subprocess.PIPE, stderr=errors, text=True,
        )
        acknowledged = 0
        try:
            selector = selectors.DefaultSelector()
            selector.register(process.stdout, selectors.EVENT_READ)
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                if not selector.select(timeout=1):
                    if process.poll() is not None:
                        break
                    continue
                line = process.stdout.readline()
                if not line and process.poll() is not None:
                    break
                if line.startswith("ACK "):
                    acknowledged = int(line.split()[1])
                    if acknowledged >= 5:
                        process.kill()
                        break
            selector.close()
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=10)
        errors.seek(0)
        assert acknowledged >= 5, f"Writer did not acknowledge five commits: {errors.read()}"
        assert process.returncode < 0, "Expected abrupt termination, not graceful closure"
    with sqlite3.connect(event) as connection:
        assert connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert connection.execute("PRAGMA foreign_key_check").fetchall() == []
        revision, data = connection.execute("SELECT revision,data FROM event").fetchone()
        assert revision >= acknowledged, (revision, acknowledged)
        assert json.loads(data)["name"] == f"Revision {revision}"
        players = connection.execute("SELECT data FROM player").fetchall()
        assert len(players) == 120
        assert all(json.loads(row[0])["name"].endswith(f"revision {revision}") for row in players)
        assert connection.execute("SELECT MAX(revision) FROM audit").fetchone()[0] == revision
    print(f"PASS: killed writer after acknowledged revision {acknowledged}; recovered complete revision {revision}, all 120 entrants, matching audit and valid database.")
