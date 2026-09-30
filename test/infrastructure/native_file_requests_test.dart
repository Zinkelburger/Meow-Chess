import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/native_file_requests.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('meow_chess/file_open');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('opens the file the app was launched with', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ready');
      return ['/events/spring.meow', '/events/ignored.meow'];
    });
    final opened = <String>[];
    await NativeFileRequests(open: opened.add).start();
    expect(opened, ['/events/spring.meow']);
  });

  test('opens a file forwarded while the app is running', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => <Object?>[]);
    final opened = <String>[];
    final files = NativeFileRequests(open: opened.add);
    await files.start();
    expect(opened, isEmpty);

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('open', ['/events/summer.meow']),
      ),
      (_) {},
    );
    expect(opened, ['/events/summer.meow']);

    files.dispose();
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('open', ['/events/after.meow']),
      ),
      (_) {},
    );
    expect(opened, ['/events/summer.meow']);
  });

  test('does nothing where the platform has no runner channel', () async {
    final opened = <String>[];
    await NativeFileRequests(open: opened.add).start();
    expect(opened, isEmpty);
  });
}
