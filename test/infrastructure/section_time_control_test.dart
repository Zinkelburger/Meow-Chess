import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import 'rating_contract_test.dart' show exportFixture, readDbf;

void main() {
  test(
    'section time controls determine individual report categories and survive mixed manifest',
    () async {
      final original = exportFixture();
      final e = original.copy(
        timeControl: 'G/90 inc/5',
        sections: [
          for (final (i, s) in original.sections.indexed)
            s.copy(timeControl: i == 0 ? 'G/45 inc/5' : ''),
        ],
      );
      expect(ratingPreflight(e), isEmpty);
      final rows = readDbf(ratingPackage(e)['TSEXPORT.DBF']!).$2;
      expect(rows.first['S_R_SYSTEM'], 'D');
      expect(rows.last['S_R_SYSTEM'], 'R');
      final dir = Directory.systemTemp.createTempSync('meow-mixed-controls-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = await writeRatingPackage(e, dir.path);
      final manifest =
          jsonDecode(File('$path/manifest.json').readAsStringSync()) as Map;
      expect(manifest['ratingSystem'], isNull);
      expect(manifest['sections'], hasLength(e.sections.length));
    },
  );
}
