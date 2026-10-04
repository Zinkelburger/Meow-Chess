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

  test('durable directory creation supports nested backup destinations', () {
    final nested = p.join(directory.path, 'copies', 'day', 'round');
    createDirectoryDurably(nested);
    expect(Directory(nested).existsSync(), true);
    syncDirectory(nested);
    publishFile(source.path, p.join(nested, 'copy.meow'));
    expect(File(p.join(nested, 'copy.meow')).readAsStringSync(), 'complete');
  });

  test('directory synchronization errors are surfaced', () {
    expect(
      () => syncDirectory(p.join(directory.path, 'missing')),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      () => syncDirectory(source.path),
      throwsA(isA<FileSystemException>()),
    );
  }, skip: Platform.isWindows);

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

  test('explicit replacement publishes the complete file over the old one', () {
    File(destination).writeAsStringSync('previous contents');
    publishFile(source.path, destination, replaceExisting: true);
    expect(File(destination).readAsStringSync(), 'complete');
    expect(source.existsSync(), false);
  });

  test('failed replacement preserves the staged file and directory', () {
    Directory(destination).createSync();
    expect(
      () => publishFile(source.path, destination, replaceExisting: true),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory(destination).existsSync(), true);
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

  test('publishes a complete package without replacing a concurrent export', () {
    final package = Directory(p.join(directory.path, 'package.partial'))
      ..createSync();
    File(
      p.join(package.path, 'results.txt'),
    ).writeAsStringSync('complete', flush: true);
    // An empty directory appearing after preflight must also survive. Ordinary
    // POSIX rename would silently replace it with this package.
    Directory(destination).createSync();
    expect(
      () => publishDirectory(package.path, destination),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory(destination).listSync(), isEmpty);
    expect(
      File(p.join(package.path, 'results.txt')).readAsStringSync(),
      'complete',
    );
    Directory(destination).deleteSync();
    publishDirectory(package.path, destination);
    expect(
      File(p.join(destination, 'results.txt')).readAsStringSync(),
      'complete',
    );
    expect(package.existsSync(), false);
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
