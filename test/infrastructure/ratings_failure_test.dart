import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';

void main() {
  for (final status in [401, 403, 429, 503]) {
    test(
      'supplement HTTP $status retains structured provider failure',
      () async {
        final client = MockClient(
          (request) async => request.url.path.endsWith('/rating-supplements')
              ? http.Response('must not be included in errors', status)
              : http.Response(
                  jsonEncode({
                    'id': '12000000',
                    'firstName': 'Test',
                    'lastName': 'Player',
                  }),
                  200,
                ),
        );
        addTearDown(client.close);
        await expectLater(
          RatingsApi(client).supplement('12000000'),
          throwsA(
            isA<MemberLookupFailure>()
                .having((e) => e.statusCode, 'status', status)
                .having((e) => e.stopsBatch, 'stops batch', true)
                .having(
                  (e) => e.message,
                  'redacted message',
                  isNot(contains('must not be included')),
                ),
          ),
        );
      },
    );
  }

  test('transport failures are redacted and stop an offline batch', () async {
    for (final error in [
      http.ClientException('secret echoed by network layer'),
      TimeoutException('secret'),
    ]) {
      final client = MockClient((_) async => throw error);
      addTearDown(client.close);
      await expectLater(
        RatingsApi(client).member('12000000', 'secret'),
        throwsA(
          isA<MemberLookupFailure>()
              .having(
                (e) => e.kind,
                'kind',
                MemberLookupFailureKind.unavailable,
              )
              .having(
                (e) => e.message,
                'redacted message',
                isNot(contains('secret')),
              ),
        ),
      );
    }
  });
}
