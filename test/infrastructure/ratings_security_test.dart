import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';

void main() {
  test(
    'credentials go only to the fixed HTTPS provider and never follow redirects',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.url.scheme, 'https');
        expect(request.url.host, 'ratings-api.uschess.org');
        expect(request.url.path, '/api/v2/members/00123456');
        expect(request.url.query, isEmpty);
        expect(request.headers['X-Api-Key'], 'private-test-key');
        expect(request.followRedirects, false);
        return http.Response(
          '',
          302,
          headers: {'location': 'https://unrelated.example/collect'},
        );
      });
      addTearDown(client.close);
      await expectLater(
        RatingsApi(client).member('00123456', 'private-test-key'),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'safe diagnostic',
            allOf(contains('302'), isNot(contains('private-test-key'))),
          ),
        ),
      );
      expect(requests, 1);
    },
  );

  test(
    'invalid IDs and empty credentials never make network requests',
    () async {
      final client = MockClient(
        (_) async => throw StateError('Must not contact provider'),
      );
      addTearDown(client.close);
      for (final id in ['123', '../member', '12345678?key=x', '１２３４５６７８']) {
        await expectLater(
          RatingsApi(client).member(id, 'key'),
          throwsA(isA<TournamentException>()),
        );
      }
      await expectLater(
        RatingsApi(client).member('00123456', '  '),
        throwsA(isA<TournamentException>()),
      );
    },
  );

  test(
    'provider status and response bodies never expose credentials in errors',
    () async {
      for (final status in [301, 307, 308, 401, 403, 404, 429, 500, 503]) {
        final client = MockClient(
          (_) async => http.Response('private-test-key', status),
        );
        addTearDown(client.close);
        await expectLater(
          RatingsApi(client).member('00123456', 'private-test-key'),
          throwsA(
            isA<TournamentException>().having(
              (e) => e.message,
              'redacted error',
              isNot(contains('private-test-key')),
            ),
          ),
        );
      }
    },
  );

  test('malformed success bodies produce redacted, typed failures', () async {
    for (final body in [
      'private-test-key',
      '[]',
      '{"id":"00123456","ratings":"private-test-key"}',
    ]) {
      final client = MockClient((_) async => http.Response(body, 200));
      addTearDown(client.close);
      await expectLater(
        RatingsApi(client).member('00123456', 'private-test-key'),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'redacted error',
            isNot(contains('private-test-key')),
          ),
        ),
      );
    }
  });

  test(
    'provider null ratings remain unknown rather than overwriting with zero',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'id': '00123456',
            'ratings': [
              {'ratingSystem': 'R', 'rating': null},
              {'ratingSystem': 'Q', 'rating': 1500},
            ],
          }),
          200,
        ),
      );
      addTearDown(client.close);
      final member = await RatingsApi(client).member('00123456', 'key');
      expect(member.id, '00123456');
      expect(member.ratings['R'], isNull);
      expect(member.ratings['Q'], 1500);
      expect(member.toJson().toString(), isNot(contains('X-Api-Key')));
    },
  );
}
