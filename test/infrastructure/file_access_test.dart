import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/diagnostics.dart';
import 'package:meow_chess/infrastructure/file_access.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('meow_chess/file_access');
  final logs = <String>[];
  void Function(String)? previousSink;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    previousSink = Diagnostics.sink;
    Diagnostics.sink = logs.add;
    logs.clear();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    Diagnostics.sink = previousSink;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  test(
    'remembers selected files and folders through device-local native bookmarks',
    () async {
      final paths = <String>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'remember');
        paths.add(call.arguments as String);
        return null;
      });
      expect(await rememberFileAccess('/Volumes/Events/October.meow'), true);
      expect(await rememberFileAccess('/Volumes/Backups'), true);
      expect(paths, ['/Volumes/Events/October.meow', '/Volumes/Backups']);
    },
  );
  test(
    'failed grants are observable without aborting other restored access',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'restore');
        return ['/Volumes/Offline'];
      });
      await restoreFileAccess();
      expect(logs.join(), contains('/Volumes/Offline'));
      expect(logs.join(), contains('unavailable'));
    },
  );
  test('remember failure does not turn a durable save into failure', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'access-failed');
    });
    expect(await rememberFileAccess('/events/saved.meow'), false);
    await restoreFileAccess();
    expect(logs.join(), contains('remember file access'));
    expect(logs.join(), contains('restore file access'));
  });
  test('portable platforms need no native grants', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      fail('No bookmark call on portable platforms');
    });
    await restoreFileAccess();
    expect(await rememberFileAccess('/events/saved.meow'), true);
  });
}
