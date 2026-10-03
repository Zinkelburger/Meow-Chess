import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/membership.dart';
import '../support.dart';

Json evidence(
  String id, {
  String? expiration = '2027-12-31',
  String checked = '2026-10-03T12:00:00Z',
  String? status = 'Active',
}) => {
  'id': id,
  'expiration': expiration,
  'status': status,
  'retrievedAt': checked,
  'provider': 'US Chess public v1',
};

void main() {
  test(
    'membership survives save/reload and rating edits, clears for a new ID',
    () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final p = c.event!.players.first;
      expect(c.recordMembership(c.event!.id, p.id, evidence(p.memberId)), true);
      expect(
        c.repository.load()!.players.first.membershipEvidence['expiration'],
        '2027-12-31',
      );
      c.savePlayer(c.event!.players.first.copy(rating: 1750));
      expect(
        c.event!.players.first.membershipEvidence['expiration'],
        '2027-12-31',
      );
      expect(c.event!.players.first.ratingEvidence['kind'], 'TD-assigned');
      c.savePlayer(c.event!.players.first.copy(memberId: '99887766'));
      expect(c.event!.players.first.membershipEvidence, isEmpty);
      expect(
        c.recordMembership(c.event!.id, p.id, evidence(p.memberId)),
        false,
      );
      expect(
        c.recordMembership('another-event', p.id, evidence('99887766')),
        false,
      );
    },
  );

  test('an older response cannot overwrite a more recent membership check', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final p = c.event!.players.first;
    c.recordMembership(c.event!.id, p.id, evidence(p.memberId));
    final revision = c.event!.revision;
    expect(
      c.recordMembership(
        c.event!.id,
        p.id,
        evidence(p.memberId, expiration: '2020-01-01', checked: '2026-10-02'),
      ),
      false,
    );
    expect(c.event!.revision, revision);
  });

  test('older event files retain previously saved membership evidence', () {
    final json = Player(
      id: 'p',
      name: 'Player',
      memberId: '12345678',
      ratingEvidence: evidence('12345678'),
    ).toJson()..remove('membershipEvidence');
    final restored = Player.fromJson(json);
    expect(restored.membershipEvidence['expiration'], '2027-12-31');
    expect(
      MembershipSummary(restored, eventDate: '2027-01-01').label,
      '2027-12-31',
    );
    expect(
      Player.fromJson(
        Player(id: 'p', name: 'Player').toJson()..remove('membershipEvidence'),
      ).membershipEvidence,
      isEmpty,
    );
  });

  test('expiration is inclusive and warnings cover the end of the event', () {
    final p = Player(
      id: 'p',
      name: 'Player',
      memberId: '12345678',
      membershipEvidence: evidence('12345678', expiration: '2026-10-03'),
    );
    MembershipSummary summary(String date, DateTime today) =>
        MembershipSummary(p, eventDate: date, now: today);
    expect(
      summary('2026-10-03', DateTime(2026, 10, 3)).severity,
      MembershipSeverity.warning,
    );
    expect(
      summary('2026-10-03', DateTime(2026, 10, 3)).detail,
      isNot(contains('before the event')),
    );
    expect(
      summary('2026-10-04', DateTime(2026, 10, 3)).detail,
      contains('Expires before the event ends'),
    );
    expect(
      summary('2026-10-03', DateTime(2026, 10, 4)).detail,
      contains('Expired as of today'),
    );
  });

  test(
    'yellow is this calendar month, red takes precedence for expired dates',
    () {
      MembershipSummary check(String expiration, DateTime now) =>
          MembershipSummary(
            Player(
              id: 'p',
              name: 'Player',
              memberId: '12345678',
              membershipEvidence: evidence('12345678', expiration: expiration),
            ),
            eventDate: '2026-01-01',
            now: now,
          );
      expect(
        check('2026-10-31', DateTime(2026, 10, 3)).severity,
        MembershipSeverity.warning,
      );
      expect(
        check('2026-10-31', DateTime(2026, 10, 3)).warning,
        'Expires this month',
      );
      expect(
        check('2026-10-02', DateTime(2026, 10, 3)).severity,
        MembershipSeverity.error,
      );
      expect(check('2026-10-02', DateTime(2026, 10, 3)).warning, 'Expired');
      expect(
        check('2026-11-01', DateTime(2026, 10, 31)).severity,
        MembershipSeverity.normal,
      );
      expect(
        check('2027-01-01', DateTime(2026, 12, 31)).severity,
        MembershipSeverity.normal,
      );
      expect(
        check('2026-12-31', DateTime(2026, 12, 31)).warning,
        'Expires this month',
      );
      expect(
        check('2026-12-31', DateTime(2027, 1, 1)).severity,
        MembershipSeverity.error,
      );
    },
  );

  test(
    'missing dates and mismatched identities never imply active membership',
    () {
      final p = Player(id: 'p', name: 'Player', memberId: '12345678');
      expect(
        MembershipSummary(p, eventDate: '2026-10-03').label,
        'Not checked',
      );
      for (final date in [null, '', '2026-02-30', 'Life']) {
        final summary = MembershipSummary(
          p.copy(membershipEvidence: evidence(p.memberId, expiration: date)),
          eventDate: '2026-10-03',
        );
        expect(summary.label, 'Date unavailable');
        expect(summary.detail, contains('no readable expiration date'));
      }
      expect(
        MembershipSummary(
          p.copy(membershipEvidence: evidence('99999999')),
          eventDate: '2026-10-03',
        ).label,
        'Not checked',
      );
      expect(
        MembershipSummary(p.copy(memberId: ''), eventDate: '2026-10-03').label,
        'No USCF ID',
      );
      expect(
        MembershipSummary(
          p.copy(membershipEvidence: evidence(p.memberId, status: 'Expired')),
          eventDate: '2026-10-03',
        ).attention,
        true,
      );
    },
  );
}
