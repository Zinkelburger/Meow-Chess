import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/diagnostics.dart';
import 'package:meow_chess/infrastructure/diagnostic_log.dart';
import 'package:meow_chess/ui/dialogs.dart';

void main() {
  testWidgets('error is logged and can be copied without dismissing it', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('meow-error-log-');
    final log = DiagnosticLog(directory);
    final previous = Diagnostics.sink;
    Diagnostics.sink = log.write;
    addTearDown(() {
      Diagnostics.sink = previous;
      directory.deleteSync(recursive: true);
    });
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = call.arguments['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const message =
        'This event may be open or awaiting recovery. Open and close it before replacing it.';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFailure(context, message),
              child: const Text('Fail'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fail'));
    await tester.pump();
    expect(log.read(), contains('ERROR error notification — shown'));
    expect(log.read(), contains(message));
    await tester.tap(find.byTooltip('Copy error message'));
    await tester.pump();
    expect(copied, message);
    await tester.pump(const Duration(minutes: 2));
    expect(find.text(message), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
  });
}
