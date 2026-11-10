// Dependency-free launcher: stdout belongs exclusively to the MCP protocol.
// Run this file directly with `dart`, not `dart run` (which may print build logs).
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length > 1) {
    stderr.writeln('Usage: dart scripts/tournament_mcp.dart [DATA_DIRECTORY]');
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final executable = root.uri
      .resolve(
        'build/tournament-cli/bundle/bin/'
        'tournament_mcp${Platform.isWindows ? '.exe' : ''}',
      )
      .toFilePath();
  if (!File(executable).existsSync()) {
    stderr.writeln(
      'Build first: dart build cli --target=tools/tournament_mcp.dart '
      '--output=build/tournament-cli',
    );
    exitCode = 1;
    return;
  }
  // A server built before the sources last changed still starts, and answers
  // with the old rules; say so where the protocol is not listening.
  final built = File(executable).lastModifiedSync();
  final newer = _newestSource(root);
  if (newer != null && newer.lastModifiedSync().isAfter(built)) {
    final name = newer.path.startsWith(root.path)
        ? newer.path
              .substring(root.path.length)
              .replaceFirst(RegExp(r'^[/\\]+'), '')
        : newer.path;
    stderr.writeln(
      'Warning: the tournament server was built before $name last changed, '
      'so it does not include that change. Rebuild: dart build cli '
      '--target=tools/tournament_mcp.dart --output=build/tournament-cli',
    );
  }
  final data = args.isEmpty
      ? root.uri.resolve('artifacts/mcp-events').toFilePath()
      : Directory(args.single).absolute.path;
  try {
    final process = await Process.start(executable, [
      '--root',
      data,
    ], mode: ProcessStartMode.inheritStdio);
    exitCode = await process.exitCode;
  } on ProcessException catch (error) {
    stderr.writeln('Could not start the tournament server: ${error.message}');
    exitCode = 1;
  }
}

/// The most recently changed file the server is built from: anything under
/// lib/, or the server's own entry point. Null when none can be read.
File? _newestSource(Directory root) {
  File? newest;
  DateTime? changed;
  void consider(File file) {
    try {
      final modified = file.lastModifiedSync();
      if (changed == null || modified.isAfter(changed!)) {
        newest = file;
        changed = modified;
      }
    } on FileSystemException {
      // A file removed meanwhile cannot be newer than the build.
    }
  }

  consider(File.fromUri(root.uri.resolve('tools/tournament_mcp.dart')));
  try {
    final lib = Directory.fromUri(root.uri.resolve('lib/'));
    for (final entry in lib.listSync(recursive: true, followLinks: false)) {
      if (entry is File && entry.path.endsWith('.dart')) consider(entry);
    }
  } on FileSystemException {
    // No sources beside the launcher: nothing to compare.
  }
  return newest;
}
