import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/save_location.dart';
import 'package:path/path.dart' as p;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('meow_chess/file_save');
  late Directory directory;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    directory = Directory.systemTemp.createTempSync('meow-save-extension-');
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  Future<String?> choose(String typed, String suggested) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => p.join(directory.path, typed),
    );
    return (await chooseSaveLocation(suggestedName: suggested))?.path;
  }

  test('an event saved without an extension still ends in .meow', () async {
    expect(
      await choose('Spring Open', 'spring-open.meow'),
      p.join(directory.path, 'Spring Open.meow'),
    );
    expect(
      await choose('Spring Open v1.2', 'spring-open.meow'),
      p.join(directory.path, 'Spring Open v1.2.meow'),
    );
    expect(
      await choose('Spring Open.MEOW', 'spring-open.meow'),
      p.join(directory.path, 'Spring Open.MEOW'),
    );
  });

  test('reports gain an extension only when none was typed', () async {
    expect(
      await choose('Standings', 'standings.csv'),
      p.join(directory.path, 'Standings.csv'),
    );
    expect(
      await choose('results.txt', 'standings.csv'),
      p.join(directory.path, 'results.txt'),
    );
  });

  test('a completed name that already exists is never replaced', () async {
    final existing = File(p.join(directory.path, 'Spring Open.meow'))
      ..writeAsStringSync('another event');
    await expectLater(
      choose('Spring Open', 'spring-open.meow'),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('Spring Open.meow already exists'),
        ),
      ),
    );
    expect(existing.readAsStringSync(), 'another event');
  });
}
