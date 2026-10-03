import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/save_location.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('meow_chess/file_save');
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('the selected Downloads path is preserved exactly', () async {
    const destination = '/home/example/Downloads/October Quads.meow';
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => destination,
    );
    final result = await chooseSaveLocation(
      suggestedName: 'october-quads.meow',
    );
    expect(result!.path, destination);
  });

  test(
    'cancel after a prior selection cannot reuse that destination',
    () async {
      String? selected = '/home/example/Downloads/october-quads.meow';
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => selected,
      );
      expect(
        await chooseSaveLocation(suggestedName: 'october-quads.meow'),
        isNotNull,
      );
      selected = null;
      expect(
        await chooseSaveLocation(suggestedName: 'october-quads.meow'),
        isNull,
      );
    },
  );

  test(
    'relative and empty results cannot save into the launch directory',
    () async {
      for (final result in ['', 'october-quads.meow']) {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => result,
        );
        await expectLater(
          chooseSaveLocation(suggestedName: 'october-quads.meow'),
          throwsFormatException,
        );
      }
    },
  );

  test('native errors propagate without choosing a fallback', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'failed'),
    );
    await expectLater(
      chooseSaveLocation(suggestedName: 'october-quads.meow'),
      throwsA(isA<PlatformException>()),
    );
  });
}
