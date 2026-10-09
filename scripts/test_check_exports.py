#!/usr/bin/env python3
"""The export gate must fail closed on missing, stale-only or unvalidated packages."""
from pathlib import Path
import tempfile
import unittest

from check_exports import CONTRACT, IMPORTER, IMPORTER_PACKAGES, RECIPROCITY_ONLY, package_issues


def write_package(root, folder):
    path = root / folder
    path.mkdir(parents=True, exist_ok=True)
    (path / 'TDEXPORT.DBF').write_bytes(b'')


class PackageIssuesTest(unittest.TestCase):
    def complete(self, root):
        for folder in (CONTRACT, RECIPROCITY_ONLY, *(f'{IMPORTER}/{n}' for n in IMPORTER_PACKAGES)):
            write_package(root, folder)

    def test_every_expected_package_present_passes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.complete(root)
            self.assertEqual(package_issues(root), [])

    def test_nothing_generated_lists_every_package(self):
        with tempfile.TemporaryDirectory() as temp:
            issues = package_issues(Path(temp))
            self.assertEqual(len(issues), len(IMPORTER_PACKAGES) + 2)

    def test_a_package_a_test_stopped_writing_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.complete(root)
            (root / IMPORTER / 'quad' / 'TDEXPORT.DBF').unlink()
            issues = package_issues(root)
            self.assertEqual(len(issues), 1)
            self.assertIn('quad', issues[0])

    def test_an_unvalidated_new_package_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.complete(root)
            write_package(root, f'{IMPORTER}/brand-new')
            issues = package_issues(root)
            self.assertEqual(len(issues), 1)
            self.assertIn('brand-new', issues[0])


if __name__ == '__main__':
    unittest.main()
