import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/diagnostics.dart';
import 'package:meow_chess/infrastructure/publish_file.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late File source;
  late String destination;
  late List<String> diagnostics;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('meow-publish-fallback-');
    source = File(p.join(directory.path, 'staged'))
      ..writeAsStringSync('complete');
    destination = p.join(directory.path, 'backup.meow');
    diagnostics = [];
    Diagnostics.sink = diagnostics.add;
  });
  tearDown(() {
    debugExclusiveRenameUnsupported = false;
    debugSyncPublishedDirectory = syncDirectory;
    Diagnostics.sink = null;
    directory.deleteSync(recursive: true);
  });

  group('without an exclusive rename', () {
    setUp(() => debugExclusiveRenameUnsupported = true);

    test('a file is still published under its new name', () {
      publishFile(source.path, destination);
      expect(File(destination).readAsStringSync(), 'complete');
      expect(source.existsSync(), isFalse);
    });

    test('an existing destination is still never replaced', () {
      File(destination).writeAsStringSync('other writer');
      expect(
        () => publishFile(source.path, destination),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(destination).readAsStringSync(), 'other writer');
      expect(source.readAsStringSync(), 'complete');
    });

    test('a dangling symlink is still preserved', () {
      final missing = p.join(directory.path, 'missing');
      Link(destination).createSync(missing);
      expect(
        () => publishFile(source.path, destination),
        throwsA(isA<FileSystemException>()),
      );
      expect(Link(destination).targetSync(), missing);
      expect(source.existsSync(), isTrue);
    });

    test('a folder is refused with a plain reason and left intact', () {
      final package = Directory(p.join(directory.path, 'package.partial'))
        ..createSync();
      File(p.join(package.path, 'results.txt')).writeAsStringSync('complete');
      final target = p.join(directory.path, 'package');
      expect(
        () => publishDirectory(package.path, target),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('cannot save a folder'),
          ),
        ),
      );
      expect(Directory(target).existsSync(), isFalse);
      expect(
        File(p.join(package.path, 'results.txt')).readAsStringSync(),
        'complete',
      );
    });
  }, skip: Platform.isWindows);

  test('a failed folder sync after publication is logged, not a failure', () {
    debugSyncPublishedDirectory = (path) =>
        throw FileSystemException('fsync failed', path);
    publishFile(source.path, destination);
    expect(File(destination).readAsStringSync(), 'complete');
    expect(
      diagnostics.where((d) => d.contains('directory sync failed')),
      isNotEmpty,
    );
  }, skip: Platform.isWindows);

  test('long Windows paths get the extended-length prefix', () {
    final folder = List.filled(30, 'Spring Open').join(r'\');
    expect(
      windowsExtendedPath(r'C:\Events\event.meow'),
      r'C:\Events\event.meow',
    );
    expect(
      windowsExtendedPath('C:/Events/$folder/event.meow'),
      '\\\\?\\C:\\Events\\$folder\\event.meow',
    );
    expect(
      windowsExtendedPath('\\\\club\\share\\$folder\\event.meow'),
      '\\\\?\\UNC\\club\\share\\$folder\\event.meow',
    );
    final prefixed = '\\\\?\\C:\\$folder\\event.meow';
    expect(windowsExtendedPath(prefixed), prefixed);
  });
}
