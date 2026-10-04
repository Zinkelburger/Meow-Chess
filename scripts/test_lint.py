"""Architecture rules must survive moving code into feature subdirectories."""
from pathlib import Path
import tempfile
import unittest

from lint import architecture_issues


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


if __name__ == '__main__':
    unittest.main()
