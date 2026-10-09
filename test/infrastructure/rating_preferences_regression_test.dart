import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meow_chess/infrastructure/diagnostic_log.dart';
import 'package:meow_chess/infrastructure/member_directory.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/ui/rating_settings.dart';

class _NoSecretService extends FlutterSecureStorage {
  const _NoSecretService();
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw StateError('No Secret Service');

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw StateError('No Secret Service');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Directory temp() {
    final dir = Directory.systemTemp.createTempSync('meow-prefs-');
    addTearDown(() => dir.deleteSync(recursive: true));
    return dir;
  }

  test(
    'the default rating category saves without a keychain and survives restart',
    () async {
      final dir = temp();
      final preference = RatingCategoryPreference(
        directory: dir,
        storage: const _NoSecretService(),
      );
      expect(await preference.read(), 'R');
      await preference.write('B');
      expect(
        await RatingCategoryPreference(
          directory: dir,
          storage: const _NoSecretService(),
        ).read(),
        'B',
      );
    },
  );

  test('by default the preference lives in the app data folder', () async {
    final dir = temp();
    DiagnosticLog.current = DiagnosticLog(Directory('${dir.path}/logs'));
    addTearDown(() => DiagnosticLog.current = null);
    await saveRatingCategory('Q');
    expect(File('${dir.path}/rating-defaults.json').existsSync(), true);
    expect(await readRatingCategory(), 'Q');
  });

  test('an older keychain category is migrated once', () async {
    FlutterSecureStorage.setMockInitialValues({'meow-rating-category': 'Q'});
    final dir = temp();
    expect(await RatingCategoryPreference(directory: dir).read(), 'Q');
    expect(
      jsonDecode(File('${dir.path}/rating-defaults.json').readAsStringSync()),
      {'category': 'Q'},
    );
    // The file now wins over whatever the keychain holds.
    FlutterSecureStorage.setMockInitialValues({'meow-rating-category': 'B'});
    expect(await RatingCategoryPreference(directory: dir).read(), 'Q');
  });

  test(
    'removing a revoked key sends lookups back to the public route',
    () async {
      await saveMemberApiKey('revoked-key');
      expect(await hasMemberApiKey(), true);
      final paths = <String>[];
      final directory = MemberDirectory(
        createClient: () => MockClient((request) async {
          paths.add(request.url.path);
          if (request.headers.containsKey('X-Api-Key')) {
            return http.Response('', 401);
          }
          return http.Response(
            jsonEncode({'id': '12000000', 'firstName': 'Test'}),
            200,
          );
        }),
      );
      await expectLater(
        directory.member('12000000'),
        throwsA(isA<MemberLookupFailure>()),
      );
      await saveMemberApiKey('  ');
      expect(await hasMemberApiKey(), false);
      expect((await directory.member('12000000')).id, '12000000');
      expect(paths, ['/api/v2/members/12000000', '/api/v1/members/12000000']);
    },
  );

  testWidgets('a saved key shows a remove control that deletes it', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({'uschess-v2': 'old-key'});
    var saved = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ApiKeyField(onSaved: () => saved++)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remove-api-key')));
    await tester.pumpAndSettle();
    expect(await hasMemberApiKey(), false);
    expect(saved, 1);
    expect(find.textContaining('Key removed'), findsOneWidget);
    expect(find.byKey(const ValueKey('remove-api-key')), findsNothing);
  });

  test('TLS failures read as an unreachable US Chess, not a crash', () async {
    for (final error in [
      const HandshakeException('Handshake error in client'),
      const TlsException('CERTIFICATE_VERIFY_FAILED'),
      const HttpException('Connection closed'),
    ]) {
      final client = MockClient((_) async => throw error);
      addTearDown(client.close);
      await expectLater(
        RatingsApi(client).member('12000000', '', publicAccess: true),
        throwsA(
          isA<MemberLookupFailure>()
              .having(
                (e) => e.kind,
                'kind',
                MemberLookupFailureKind.unavailable,
              )
              .having(
                (e) => e.message,
                'message',
                startsWith('Could not reach US Chess'),
              ),
        ),
      );
    }
  });
}
