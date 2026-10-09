#!/usr/bin/env python3
"""TD ID fields must hold only IDs; anything else would pass through unanonymized."""
from pathlib import Path
import shutil
import tempfile
import unittest

from anonymize_boylston import Identities, Table, anonymize_event, td_value

FIXTURE = Path(__file__).resolve().parents[1] / 'test/fixtures/boylston/tornado-147'


class TdFieldTests(unittest.TestCase):
    def test_ids_are_mapped(self):
        ids = Identities()
        self.assertEqual(td_value(b'12345678   ', ids, 'H_CTD_ID'), b'90000001')
        self.assertEqual(td_value(b'12345678,23456789', ids, 'H_OTHER_TD'), b'90000001,90000002')
        self.assertEqual(td_value(b'12345678, 23456789 ', ids, 'H_OTHER_TD'), b'90000001, 90000002')
        self.assertEqual(td_value(b'        ', ids, 'H_ATD_ID'), b'')

    def test_anything_else_is_refused(self):
        for value in (b'J SMITH', b'1234567', b'123456789', b'12345678 JONES', b'12345678;23456789'):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'unexpected TD ID content'):
                td_value(value, Identities(), 'H_OTHER_TD')

    def test_event_with_a_name_in_a_td_field_is_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / 'event'
            folder.mkdir()
            for name in ('THEXPORT', 'TSEXPORT', 'TDEXPORT'):
                shutil.copy(FIXTURE / f'{name}.DBF', folder / f'{name.lower()}.dbf')
            header = Table(folder / 'thexport.dbf')
            header.put(0, 'H_OTHER_TD', b'90000133, Real Person')
            (folder / 'thexport.dbf').write_bytes(header.raw)
            with self.assertRaisesRegex(ValueError, 'event: H_OTHER_TD'):
                anonymize_event(folder, Identities())


if __name__ == '__main__':
    unittest.main()
