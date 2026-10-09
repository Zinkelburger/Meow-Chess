#!/usr/bin/env python3
"""Negative controls: independent validation must reject plausible corrupt exports."""
from contextlib import redirect_stdout
import io
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
from dbfread import DBF
from verify_dbf import DbfCheckError, verify

VERIFIER = Path(__file__).resolve().parent / 'verify_dbf.py'
# Cases the schema and reciprocity checks alone accept: only the source-event
# oracle (expected-event.json) can catch them.
ORACLE_ONLY = {'wrong-results', 'wrong-identity', 'extra-entrant'}


def quiet(folder, reciprocity_only=False):
    with redirect_stdout(io.StringIO()):
        verify(folder, reciprocity_only)


def rejected(folder, reciprocity_only=False):
    try:
        quiet(folder, reciprocity_only)
    except (DbfCheckError, ValueError, KeyError):
        return
    raise AssertionError(f'Validator accepted a deliberately damaged export: {folder.name}')


def layout(raw, path):
    """Each field's (offset within a record, width), after the deletion flag."""
    table = DBF(str(path), encoding='ascii')
    count, header, size = struct.unpack_from('<IHH', raw, 4)
    fields, offset = {}, 1
    for field in table.fields:
        fields[field.name] = (offset, field.length)
        offset += field.length
    return count, header, size, fields


def put(raw, path, row, name, value):
    count, header, size, fields = layout(raw, path)
    offset, width = fields[name]
    start = header + row * size + offset
    raw[start:start + width] = value.ljust(width).encode('ascii')


def get(raw, path, row, name):
    count, header, size, fields = layout(raw, path)
    offset, width = fields[name]
    start = header + row * size + offset
    return raw[start:start + width].decode('ascii').strip()


def damage(case, folder):
    path = folder / ('TSEXPORT.DBF' if case in ('wrong-rating-system', 'padding') else 'TDEXPORT.DBF')
    raw = bytearray(path.read_bytes())
    count, header, size, fields = layout(raw, path)
    if case == 'field-type':
        raw[32 + 11] = ord('N')
    elif case == 'truncated':
        raw = raw[:-8]
    elif case == 'deleted-record':
        raw[header] = ord('*')
    elif case == 'eof-byte':
        raw[-1] = 0
    elif case == 'header-length':
        # A header length that disagrees with the field descriptors.
        struct.pack_into('<H', raw, 8, header + 1)
    elif case == 'non-ascii':
        offset, _ = fields['D_NAME']
        raw[header + offset] = 0xC9
    elif case == 'padding':
        # Section 1 now claims 11 rounds, so its played round 12 sits in a
        # column that must be the U0 padding.
        put(raw, path, 0, 'S_TOT_RNDS', '11')
    elif case == 'unknown-opponent':
        # Reciprocity would look up a pair number that does not exist.
        put(raw, path, 0, 'D_RND01', 'W99W')
    elif case == 'bad-date':
        path = folder / 'THEXPORT.DBF'
        raw = bytearray(path.read_bytes())
        put(raw, path, 0, 'H_BEG_DATE', '20261399')
    elif case == 'self-opponent':
        put(raw, path, 0, 'D_RND01', f"W{get(raw, path, 0, 'D_PAIR_NUM')}W")
    elif case == 'wrong-identity':
        # One entrant, so the duplicate-ID check cannot be what catches it.
        put(raw, path, 0, 'D_MEM_ID', '99999999')
    elif case == 'blank-state':
        put(raw, path, 0, 'D_STATE', '')
    elif case == 'wrong-name':
        offset, _ = fields['D_NAME']
        raw[header + offset:header + offset + 5] = b'XXXXX'
    elif case == 'wrong-results':
        for row in range(count):
            for name, (offset, _) in fields.items():
                # Flip BOTH sides: still reciprocal, but not the actual
                # event results. Only the source-event oracle catches it.
                at = header + row * size + offset
                if name.startswith('D_RND') and raw[at] in (ord('W'), ord('L')):
                    raw[at] = ord('L') if raw[at] == ord('W') else ord('W')
    elif case == 'wrong-rating-system':
        for row in range(count):
            # A plausible code that contradicts the time control.
            at = header + row * size + fields['S_R_SYSTEM'][0]
            raw[at] = ord('Q') if raw[at] != ord('Q') else ord('R')
    elif case == 'extra-entrant':
        # A phantom, unpaired entrant appended to section 1 with consistent
        # counts everywhere: schema and reciprocity both still hold.
        section = get(raw, path, 0, 'D_SEC_NUM')
        last = max(int(get(raw, path, r, 'D_PAIR_NUM')) for r in range(count)
                   if get(raw, path, r, 'D_SEC_NUM') == section)
        record = bytearray(raw[header:header + size])
        raw = raw[:-1] + record + b'\x1a'
        struct.pack_into('<I', raw, 4, count + 1)
        put(raw, path, count, 'D_PAIR_NUM', str(last + 1))
        put(raw, path, count, 'D_MEM_ID', '99999998')
        for name in fields:
            if name.startswith('D_RND'):
                put(raw, path, count, name, 'U0')
        sections = folder / 'TSEXPORT.DBF'
        summary = bytearray(sections.read_bytes())
        rows = layout(summary, sections)[0]
        for row in range(rows):
            if get(summary, sections, row, 'S_SEC_NUM') == section:
                put(summary, sections, row, 'S_LST_PAIR', str(last + 1))
        sections.write_bytes(summary)
    path.write_bytes(raw)


def run(source):
    with tempfile.TemporaryDirectory(prefix='meow-dbf-negative-') as temp:
        for case in ['field-type', 'truncated', 'wrong-results', 'wrong-identity',
                     'wrong-rating-system', 'blank-state', 'wrong-name', 'deleted-record',
                     'eof-byte', 'header-length', 'non-ascii', 'padding', 'self-opponent',
                     'extra-entrant', 'unknown-opponent', 'bad-date']:
            folder = Path(temp) / case
            shutil.copytree(source, folder)
            damage(case, folder)
            rejected(folder)
            if case == 'padding':
                # Without the oracle, only the padding check is left to catch it.
                (folder / 'expected-event.json').unlink()
                rejected(folder, reciprocity_only=True)
            if case in ORACLE_ONLY:
                # Proves the case exercises the oracle, not an earlier check.
                (folder / 'expected-event.json').unlink()
                quiet(folder, reciprocity_only=True)
        # No source event: an error unless explicitly downgraded.
        folder = Path(temp) / 'no-oracle'
        shutil.copytree(source, folder)
        (folder / 'expected-event.json').unlink()
        rejected(folder)
        quiet(folder, reciprocity_only=True)
        # Explicit checks survive python -O, which strips assert statements.
        for case in ['wrong-identity', 'padding', 'extra-entrant']:
            folder = Path(temp) / f'optimized-{case}'
            shutil.copytree(source, folder)
            damage(case, folder)
            result = subprocess.run([sys.executable, '-O', str(VERIFIER), str(folder)],
                                    capture_output=True, text=True)
            if result.returncode != 1 or 'FAIL' not in result.stderr:
                raise AssertionError(f'python -O accepted {case}: {result.returncode} {result.stdout}')
        result = subprocess.run([sys.executable, '-O', str(VERIFIER), str(source)], capture_output=True, text=True)
        if result.returncode != 0:
            raise AssertionError(f'python -O rejected the clean export: {result.stderr}')
        # Unreadable or undecodable packages fail with a FAIL line, not a crash.
        missing = Path(temp) / 'missing-file'
        shutil.copytree(source, missing)
        (missing / 'TDEXPORT.DBF').unlink()
        cli_failures = {'missing-file': missing}
        for case in ['unknown-opponent', 'bad-date', 'truncated']:
            folder = Path(temp) / f'cli-{case}'
            shutil.copytree(source, folder)
            damage(case, folder)
            cli_failures[case] = folder
        for case, folder in cli_failures.items():
            result = subprocess.run([sys.executable, str(VERIFIER), str(folder)], capture_output=True, text=True)
            if result.returncode != 1 or not result.stderr.startswith('FAIL: ') or 'Traceback' in result.stderr:
                raise AssertionError(f'{case} did not fail cleanly: {result.returncode} {result.stderr}')
    print('PASS: validator rejects wrong field types, truncation, reciprocal-but-wrong results, a wrong member ID, '
          'a rating system that contradicts the time control, a blank state, a wrong name, a deleted record, '
          'a bad EOF byte, a bad header length, a non-ASCII byte, non-U0 padding, a self opponent, a phantom '
          'entrant, an unknown opponent, an impossible date and a missing expected-event.json, also under '
          'python -O, and reports unreadable packages as FAIL lines rather than tracebacks.')


if __name__ == '__main__':
    run(Path(sys.argv[1]))
