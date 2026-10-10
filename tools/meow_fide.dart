// The FIDE Pairings and Tie-Breaks Checker and Random Tournament Generator
// as a command-line program. Build it with
//   dart build cli --target=tools/meow_fide.dart --output=build/fide-cli
// (the FIDE Dutch engine is a native library the build bundles), then run
// build/fide-cli/bundle/bin/meow_fide --help.
import 'dart:io';

import 'package:meow_chess/infrastructure/fide_cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runFideCli(args);
}
