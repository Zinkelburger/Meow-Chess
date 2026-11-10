import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/us_chess.dart';
import 'package:meow_chess/infrastructure/roster_import.dart';

void main() {
  test('ratings keep their number and lose their decoration', () {
    const ratings = {
      '1500': 1500,
      '1500P12': 1500,
      '1500p': 1500,
      '1234/5': 1234,
      '1500.0': 1500,
      '1500*': 1500,
      '1500 P5': 1500,
      '(1450)': 1450,
      '0': 0,
      '': 0,
      'Unr.': 0,
      'UNR': 0,
      'unrated': 0,
      'NR': 0,
      'New': 0,
      '-': 0,
      'n/a': 0,
    };
    for (final MapEntry(:key, :value) in ratings.entries) {
      expect(rosterRating(key), value, reason: '"$key"');
    }
    for (final odd in ['strong', '15000', 'A1500']) {
      expect(rosterRating(odd), isNull, reason: odd);
    }
  });

  test('IDs are eight digits, nothing, or flagged', () {
    const ids = {
      '12345678': '12345678',
      '00123456': '00123456',
      ' 12345678 ': '12345678',
      '12345678.0': '12345678',
      '#12345678': '12345678',
      '': '',
      'NEW': '',
      'pending': '',
      'none': '',
      '-': '',
      'n/a': '',
      '0': '',
    };
    for (final MapEntry(:key, :value) in ids.entries) {
      expect(rosterMemberId(key), value, reason: '"$key"');
    }
    for (final odd in ['1234567', '123456789', 'A1234567', 'abc']) {
      expect(rosterMemberId(odd), isNull, reason: odd);
    }
  });

  test('state names become their two-letter code', () {
    expect(stateCodeOf('Massachusetts'), 'MA');
    expect(stateCodeOf('new  york'), 'NY');
    expect(stateCodeOf('D.C.'), 'DC');
    expect(stateCodeOf('ma'), 'MA');
    expect(stateCodeOf('ON'), 'ON');
    expect(stateCodeOf('Ontario'), isNull);
  });

  test('only a missing name keeps a row out; odd fields are warnings', () {
    final rows = parseRoster(
      'Name,ID,Rating,State\n'
      'Ada Lee,12345678,1500P12,Massachusetts\n'
      'Bo Chen,NEW,Unr.,NH\n'
      'Cy Diaz,1234567,1234/5,Ontario\n'
      'Di Evans,pending,strong,\n'
      ',12345679,1400,MA\n',
    );
    expect(rows.map((r) => r.error), [null, null, null, null, 'Missing name']);
    final [ada, bo, cy, di, _] = rows;
    expect(
      (ada.player!.memberId, ada.player!.rating, ada.player!.state),
      ('12345678', 1500, 'MA'),
    );
    expect(ada.warnings, isEmpty);
    expect(
      (bo.player!.memberId, bo.player!.rating, bo.player!.state),
      ('', 0, 'NH'),
    );
    expect(bo.warnings, isEmpty);
    expect(
      (cy.player!.memberId, cy.player!.rating, cy.player!.state),
      ('', 1234, ''),
    );
    expect(cy.warnings, [
      contains('"1234567" is not eight digits'),
      contains('"Ontario" is not a state'),
    ]);
    expect((di.player!.memberId, di.player!.rating), ('', 0));
    expect(di.warnings.single, contains('Rating "strong"'));

    expect(
      importWarningSummary(rows),
      'imported without a US Chess ID (not eight digits): Cy Diaz · '
      'imported without a state: Cy Diaz · '
      'imported as unrated (rating not a number): Di Evans',
    );
    expect(importWarningSummary([ada, bo]), '');
  });
}
