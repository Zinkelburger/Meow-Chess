#!/usr/bin/env python3
"""Negative controls: independent validation must reject plausible corrupt exports."""
from contextlib import redirect_stdout
import io
from pathlib import Path
import shutil
import struct
import sys
import tempfile
from dbfread import DBF
from verify_dbf import verify


def rejected(folder):
    try:
        with redirect_stdout(io.StringIO()):
            verify(folder)
    except (AssertionError, ValueError, KeyError):
        return
    raise AssertionError('Validator accepted a deliberately damaged export')


def run(source):
    with tempfile.TemporaryDirectory(prefix='meow-dbf-negative-') as temp:
        for case in ['field-type', 'truncated', 'wrong-results', 'wrong-identity']:
            folder = Path(temp) / case
            shutil.copytree(source, folder)
            path = folder / 'TDEXPORT.DBF'
            raw = bytearray(path.read_bytes())
            if case == 'field-type':
                raw[32 + 11] = ord('N')
            elif case == 'truncated':
                raw = raw[:-8]
            else:
                table = DBF(str(path), encoding='ascii')
                count, header, size = struct.unpack_from('<IHH', raw, 4)
                for row in range(count):
                    offset = header + row * size + 1
                    for field in table.fields:
                        if case == 'wrong-results' and field.name.startswith('D_RND'):
                            # Flip BOTH sides: still reciprocal, but not the actual
                            # event results. Only the source-event oracle catches it.
                            if raw[offset] in (ord('W'), ord('L')):
                                raw[offset] = ord('L') if raw[offset] == ord('W') else ord('W')
                        if case == 'wrong-identity' and field.name == 'D_MEM_ID':
                            raw[offset:offset + 8] = b'99999999'
                        offset += field.length
            path.write_bytes(raw)
            rejected(folder)
    print('PASS: validator rejects wrong field types, truncation, reciprocal-but-wrong results and wrong member IDs.')


if __name__ == '__main__':
    run(Path(sys.argv[1]))
