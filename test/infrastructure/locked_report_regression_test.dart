import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/failures.dart';
import 'package:meow_chess/infrastructure/artifact_file.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late String report;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('meow-locked-report-');
    report = p.join(directory.path, 'standings.csv');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  FileSystemException failure(int code) => FileSystemException(
    'Could not publish the complete file',
    report,
    OSError('Atomic rename failed', code),
  );

  test('a report open in Excel is explained in plain words', () {
    for (final code in [32, 33]) {
      expect(
        plainMessage(
          lockedDestinationError(failure(code), report, windows: true)!,
        ),
        'standings.csv is open in another program. Close it there and try again.',
      );
    }
    File(report).writeAsStringSync('old');
    expect(
      lockedDestinationError(failure(5), report, windows: true)!.message,
      contains('may be open in another program'),
    );
  });

  test('other failures keep their own explanation', () {
    // Access denied on a new name is a permissions problem, not a lock.
    expect(lockedDestinationError(failure(5), report, windows: true), isNull);
    expect(lockedDestinationError(failure(2), report, windows: true), isNull);
    // POSIX errno 32 is EPIPE, unrelated to sharing.
    expect(lockedDestinationError(failure(32), report, windows: false), isNull);
  });
}
