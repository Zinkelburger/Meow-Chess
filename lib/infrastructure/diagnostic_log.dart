import 'dart:io';
import 'package:path/path.dart' as p;
import '../application/diagnostics.dart';

/// Two bounded UTF-8 text files in the platform application-support
/// directory. No network uploads or full roster/provider payloads.
class DiagnosticLog {
  DiagnosticLog(Directory directory, {this.maxBytes = 2 * 1024 * 1024})
    : file = File(p.join(directory.path, 'diagnostics.log'));
  final File file;
  final int maxBytes;
  static DiagnosticLog? current;
  File get previous => File('${file.path}.previous');

  void write(String line) {
    file.parent.createSync(recursive: true);
    if (file.existsSync() && file.lengthSync() >= maxBytes) {
      if (previous.existsSync()) previous.deleteSync();
      file.renameSync(previous.path);
    }
    file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  }

  String read() => [
    if (previous.existsSync()) previous.readAsStringSync(),
    if (file.existsSync()) file.readAsStringSync(),
  ].join();

  static void initialize(Directory directory) {
    final log = current = DiagnosticLog(
      Directory(p.join(directory.path, 'logs')),
    );
    Diagnostics.sink = (line) {
      try {
        stderr.writeln(line);
      } catch (_) {
        /* No attached console. */
      }
      log.write(line);
    };
    Diagnostics.record(
      'application',
      'started',
      context: {
        'platform': Platform.operatingSystem,
        'runtime': Platform.version,
        'log': log.file.path,
      },
    );
  }
}
