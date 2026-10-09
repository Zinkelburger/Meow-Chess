import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/history.dart';
import 'package:meow_chess/domain/membership.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/name_match.dart';
import 'package:meow_chess/domain/round_clock.dart';
import 'package:meow_chess/domain/us_chess.dart';

void main() {
  group('roster duplicates', () {
    test('names match across spacing, case and accents', () {
      final existing = [Player(id: 'a', name: 'jose  perez')];
      expect(
        newEntries(existing, [Player(id: 'b', name: ' José Pérez ')]),
        isEmpty,
      );
      expect(nameKey('Nguyễn  Văn\tAn'), 'nguyen van an');
    });

    test('the placeholder ID 00000000 is not an identity', () {
      expect(isMemberId('00000000'), false);
      final existing = [Player(id: 'a', name: 'Ann Lee', memberId: '00000000')];
      final added = newEntries(existing, [
        Player(id: 'b', name: 'Bob Ray', memberId: '00000000'),
        Player(id: 'c', name: 'Cy Dunn', memberId: '00000000'),
      ]);
      expect(added.map((p) => p.id), ['b', 'c']);
    });
  });

  test('history summaries never split an emoji', () {
    final before = Event(id: 'e', name: 'Club', date: '2026-10-09');
    final changes = describeChanges(
      before,
      before.copy(notes: '${'a' * 38}😀 and more text after it'),
    );
    expect(changes.single, contains('${'a' * 38}😀…”'));
    final units = changes.single.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final high = units[i] >= 0xD800 && units[i] <= 0xDBFF;
      if (high) {
        expect(units[i + 1], inInclusiveRange(0xDC00, 0xDFFF));
        i++;
      }
    }
  });

  group('rating report names', () {
    test('Vietnamese letters fold to plain capitals', () {
      // Was null. Which word is the family name is left to the TD.
      expect(reportName('Nguyễn Văn An'), isNotNull);
      expect(reportText('Nguyễn Văn An'), 'Nguyen Van An');
      expect(reportName('Trần Thị Mai'), 'MAI, TRAN THI');
      expect(reportText('Trần Hưng Đạo'), 'Tran Hung Dao');
      expect(reportText('Lê Thị Phượng'), 'Le Thi Phuong');
      expect(reportText('Ơn Ưng'), 'On Ung');
    });

    test('a last name with only a suffix stays together', () {
      expect(reportName('Smith Jr'), 'SMITH JR');
      expect(reportName('Smith, Jr.'), 'SMITH JR.');
      expect(reportName('John Smith Jr'), 'SMITH, JOHN JR');
    });
  });

  test('name particles are not evidence of the same person', () {
    expect(namesLookAlike('La Shawn Smith', 'Juan De La Cruz'), false);
    expect(namesLookAlike('Anna van Dyke', 'Pieter van Buren'), false);
    expect(
      namesLookAlike(
        'Juan de la Cruz',
        'Juan De La Cruz',
        lastName: lastNameOf('DE LA CRUZ, JUAN'),
      ),
      true,
    );
    // A surname that is itself a particle still has to match.
    expect(namesLookAlike('Minh Le', 'Le Minh', lastName: 'LE'), true);
    expect(namesLookAlike('Minh Tran', 'Le Minh', lastName: 'LE'), false);
  });

  group('membership is judged at the event once it has passed', () {
    final today = DateTime(2026, 10, 9);
    MembershipSummary summary(String expiration, String eventDate) =>
        MembershipSummary(
          Player(
            id: 'p',
            name: 'Player',
            memberId: '12345678',
            membershipEvidence: {
              'id': '12345678',
              'expiration': expiration,
              'status': 'Active',
              'retrievedAt': '2026-10-09T12:00:00Z',
            },
          ),
          eventDate: eventDate,
          now: today,
        );

    test('valid at a past event is not flagged', () {
      final s = summary('2026-09-30', '2026-09-15');
      expect(s.severity, MembershipSeverity.normal);
      expect(s.warning, isNull);
      expect(s.detail, isNot(contains('Expired')));
      // Nor is "this month" news about an event already played.
      expect(summary('2026-10-20', '2026-09-15').warning, isNull);
    });

    test('lapsed before a past event ended is an error', () {
      final s = summary('2026-09-01', '2026-09-15');
      expect(s.severity, MembershipSeverity.error);
      expect(s.warning, 'Expired before event ended');
      expect(
        s.detail,
        contains('Expired before the event ended (2026-09-15).'),
      );
      expect(s.detail, isNot(contains('as of today')));
    });

    test('an upcoming event warns about today and the event', () {
      expect(
        summary('2026-11-01', '2026-11-15').warning,
        'Expires before event ends',
      );
      expect(summary('2026-10-20', '2026-11-15').warning, 'Expires this month');
      final expired = summary('2026-10-01', '2026-11-15');
      expect(expired.warning, 'Expired');
      expect(expired.detail, contains('Expired as of today.'));
    });

    test('the placeholder ID reads as no ID', () {
      final p = Player(id: 'p', name: 'Player', memberId: '00000000');
      expect(MembershipSummary(p, eventDate: '2026-10-09').label, 'No USCF ID');
    });
  });

  test('round estimates accept the app\'s own time control spellings', () {
    final start = DateTime(2026, 10, 9, 10);
    Duration? length(String control) =>
        estimateRoundFinish(control, start)?.finish.difference(start);
    const sixtyDelayFive = Duration(minutes: 120, seconds: 400);
    expect(length('G/60;d5'), sixtyDelayFive);
    expect(length('G/60 d/5'), sixtyDelayFive);
    expect(length(TimeControl.parse('G/60 d5').uscfText), sixtyDelayFive);
    expect(length('G/90 inc/30'), const Duration(minutes: 180, seconds: 2400));
    expect(length('G/90;+30'), const Duration(minutes: 180, seconds: 2400));
    expect(length('Game/45'), const Duration(minutes: 90));
    expect(length('G/65 d10'), const Duration(minutes: 143, seconds: 20));
    expect(length('40/90, SD/30 d/5'), isNull);
    expect(length('casual'), isNull);
  });
}
