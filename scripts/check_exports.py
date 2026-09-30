#!/usr/bin/env python3
"""Generate and independently validate synthetic exports (requires dbfread==2.0.7)."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
subprocess.run(['flutter', 'test', '--concurrency=2', 'test/infrastructure/rating_contract_test.dart'], cwd=root, env={**os.environ, 'MEOW_EXPORT_FIXTURES': '1'}, check=True)
subprocess.run([sys.executable, 'scripts/verify_dbf.py', 'artifacts/dbf-contract'], cwd=root, check=True)
