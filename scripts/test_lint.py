"""Architecture rules must survive moving code into feature subdirectories."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from lint import architecture_issues, release_issues, whitespace_issues


def write_metainfo(root, *versions):
    metainfo = root / 'packaging/flatpak/org.meowchess.meow_chess.metainfo.xml'
    metainfo.parent.mkdir(parents=True, exist_ok=True)
    releases = ''.join(f'<release version="{v}" date="2026-10-01" />' for v in versions)
    metainfo.write_text(f'<component><releases>{releases}</releases></component>', encoding='utf-8')


class ArchitectureTest(unittest.TestCase):
    def test_nested_relative_and_package_imports_cannot_cross_layers(self):
        for directive in ["import '../../infrastructure/store.dart';",
                          "export 'package:meow_chess/ui/view.dart';",
                          "import '../../application/controller.dart';"]:
            with self.subTest(directive=directive), tempfile.TemporaryDirectory() as temp:
                root = Path(temp).resolve()
                file = root / 'lib/domain/ratings/policy.dart'
                file.parent.mkdir(parents=True)
                file.write_text(directive, encoding='utf-8')
                self.assertEqual(len(architecture_issues(root)), 1)

    def test_application_can_use_domain_but_not_adapters(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            file = root / 'lib/application/ratings/batch.dart'
            file.parent.mkdir(parents=True)
            file.write_text("import '../../domain/member.dart';", encoding='utf-8')
            self.assertEqual(architecture_issues(root), [])
            file.write_text("import 'package:meow_chess/infrastructure/api.dart';", encoding='utf-8')
            self.assertEqual(len(architecture_issues(root)), 1)


class ReleaseVersionTest(unittest.TestCase):
    def test_package_exporter_and_tag_must_agree(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'lib').mkdir()
            (root / 'pubspec.yaml').write_text('version: 1.2.0+4\n', encoding='utf-8')
            source = root / 'lib/version.dart'
            source.write_text("const appVersion = '1.2.0';\n", encoding='utf-8')
            write_metainfo(root, '1.2.0', '1.1.1')
            self.assertEqual(release_issues(root, 'refs/tags/v1.2.0'), [])
            self.assertEqual(len(release_issues(root, 'refs/tags/v1.1.1')), 1)
            source.write_text("const appVersion = '1.1.1';\n", encoding='utf-8')
            self.assertEqual(len(release_issues(root)), 1)

    def test_newest_metainfo_release_must_be_the_package_version(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'lib').mkdir()
            (root / 'pubspec.yaml').write_text('version: 1.2.3+7\n', encoding='utf-8')
            (root / 'lib/version.dart').write_text("const appVersion = '1.2.3';\n", encoding='utf-8')
            write_metainfo(root, '1.2.3', '1.2.0')
            self.assertEqual(release_issues(root), [])
            write_metainfo(root, '1.2.0', '1.1.1')
            self.assertEqual(len(release_issues(root)), 1)
            (root / 'packaging/flatpak/org.meowchess.meow_chess.metainfo.xml').unlink()
            self.assertEqual(len(release_issues(root)), 1)


class WhitespaceTest(unittest.TestCase):
    def git(self, root, *args):
        subprocess.run(['git', '-c', 'user.name=Lint', '-c', 'user.email=lint@example.com',
                        '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', *args],
                       cwd=root, check=True, capture_output=True)

    def test_committed_whitespace_fails_even_on_a_clean_checkout(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.git(root, 'init', '-q')
            (root / 'clean.txt').write_text('fine\n', encoding='utf-8')
            self.git(root, 'add', '.')
            self.git(root, 'commit', '-q', '-m', 'clean')
            self.assertEqual(whitespace_issues(root), [])
            (root / 'dirty.txt').write_text('trailing \n', encoding='utf-8')
            self.git(root, 'add', '.')
            self.git(root, 'commit', '-q', '-m', 'dirty')
            # Nothing uncommitted, which a plain `git diff --check` would pass.
            self.assertNotEqual(whitespace_issues(root), [])

    def test_verbatim_third_party_files_are_exempt(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.git(root, 'init', '-q')
            license = root / 'assets/fonts/LICENSE-Example.txt'
            license.parent.mkdir(parents=True)
            license.write_text('Copyright \r\n', encoding='utf-8')
            self.git(root, 'add', '.')
            self.git(root, 'commit', '-q', '-m', 'license')
            self.assertEqual(whitespace_issues(root), [])


if __name__ == '__main__':
    unittest.main()
