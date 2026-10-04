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
