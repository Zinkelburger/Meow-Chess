import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/main.dart';
import '../support.dart';

void main() {
  testWidgets(
    'a failed desktop open explains the problem in the current event',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final directory = Directory.systemTemp.createTempSync(
        'meow-open-feedback-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final eventPath = '${directory.path}/event.meow';
      fixture(path: eventPath).dispose();
      await tester.pumpWidget(
        MeowApp(dataDirectory: directory, initialPath: eventPath),
      );
      await tester.pumpAndSettle();
      const channel = MethodChannel('meow_chess/file_open');
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(
              MethodCall('open', ['${directory.path}/missing.meow']),
            ),
            (_) {},
          );
      await tester.pumpAndSettle();
      expect(find.text('Saturday Quads'), findsWidgets);
      expect(find.textContaining('Could not open this event'), findsOneWidget);
      expect(find.text('Player 00', findRichText: true), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
