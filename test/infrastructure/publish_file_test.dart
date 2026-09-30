import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/publish_file.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late File source;
  late String destination;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('meow-publish-');
    source = File(p.join(directory.path, 'staged'))
      ..writeAsStringSync('complete');
    destination = p.join(directory.path, 'backup-é.meow');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('publishes the complete file and removes its staging name', () {
    publishFile(source.path, destination);
    expect(File(destination).readAsStringSync(), 'complete');
    expect(source.existsSync(), false);
  });

  test('a destination created after preflight survives publication', () {
    expect(File(destination).existsSync(), false);
    // Model the other writer winning between preflight and publication.
    File(destination).writeAsStringSync('other writer');
    expect(
      () => publishFile(source.path, destination),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(destination).readAsStringSync(), 'other writer');
    expect(source.readAsStringSync(), 'complete');
  });

  test('publication preserves an existing directory', () {
    Directory(destination).createSync();
    expect(
      () => publishFile(source.path, destination),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory(destination).existsSync(), true);
    expect(source.existsSync(), true);
  });

  test('publication preserves a dangling symlink', () {
    final missing = p.join(directory.path, 'missing');
    Link(destination).createSync(missing);
    expect(
      () => publishFile(source.path, destination),
      throwsA(isA<FileSystemException>()),
    );
    expect(Link(destination).targetSync(), missing);
    expect(source.existsSync(), true);
  }, skip: Platform.isWindows);
}
