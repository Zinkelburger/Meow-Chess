import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/artifact_save.dart';

import '../support.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('meow_chess/artifact_file');
  late Directory destinationDirectory, replacementDirectory;
  late String destination;
  setUp(() {
    destinationDirectory = Directory.systemTemp.createTempSync(
      'meow-selected-',
    );
    replacementDirectory = Directory.systemTemp.createTempSync(
      'meow-replacement-',
    );
    destination = '${destinationDirectory.path}/report.csv';
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    destinationDirectory.deleteSync(recursive: true);
    if (replacementDirectory.existsSync()) {
      replacementDirectory.deleteSync(recursive: true);
    }
  });

  test(
    'macOS stages in the native replacement directory, not beside the selected file',
    () async {
      File(destination).writeAsStringSync('previous');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'stagingDirectory') {
          expect(call.arguments, destination);
          return replacementDirectory.path;
        }
        expect(call.method, 'publish');
        final args = Map<String, String>.from(call.arguments);
        expect(args['destination'], destination);
        expect(File(args['source']!).parent.path, replacementDirectory.path);
        expect(File(args['source']!).readAsBytesSync(), [1, 2, 3]);
        expect(destinationDirectory.listSync().map((f) => f.path), [
          destination,
        ]);
        File(args['source']!).copySync(destination);
        return null;
      });
      await writeSelectedArtifact(destination, [1, 2, 3]);
      expect(File(destination).readAsBytesSync(), [1, 2, 3]);
      expect(replacementDirectory.existsSync(), false);
    },
  );

  test(
    'native publication failure preserves the original and cleans staging',
    () async {
      File(destination).writeAsStringSync('previous');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'stagingDirectory') return replacementDirectory.path;
        throw PlatformException(
          code: 'artifact-save',
          message: 'Disk unavailable',
        );
      });
      await expectLater(
        writeSelectedArtifact(destination, [1]),
        throwsA(isA<PlatformException>()),
      );
      expect(File(destination).readAsStringSync(), 'previous');
      expect(replacementDirectory.existsSync(), false);
    },
  );

  test(
    'a database appearing during native staging is protected before publication',
    () async {
      var published = false;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'stagingDirectory') {
          fixture(path: destination).dispose();
          return replacementDirectory.path;
        }
        published = true;
        return null;
      });
      await expectLater(
        writeSelectedArtifact(destination, [1]),
        throwsA(isA<TournamentException>()),
      );
      expect(published, false);
      expect(
        File(destination).readAsBytesSync().take(16),
        'SQLite format 3\u0000'.codeUnits,
      );
      expect(replacementDirectory.existsSync(), false);
    },
  );
}
