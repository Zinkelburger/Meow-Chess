import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles the vendored BBP Pairings engine (third_party/bbpPairings) into
/// the dynamic library behind `lib/engine/bbp_pairings.dart`, the FIDE Dutch
/// pairing engine for FIDE-rated Swiss sections.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final root = input.packageRoot.resolve('third_party/bbpPairings/');
    final src = Directory.fromUri(root.resolve('src/'));
    final sources = [
      'third_party/bbpPairings/meow/meow_bbp.cpp',
      for (final file in src.listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.cpp') && !file.path.endsWith('main.cpp'))
          'third_party/bbpPairings/src/${file.uri.path.substring(src.uri.path.length)}',
    ]..sort();
    final windows = input.config.code.targetOS == OS.windows;
    await CBuilder.library(
      name: 'bbp_pairings',
      assetName: 'engine/bbp_pairings.dart',
      language: Language.cpp,
      std: 'c++20',
      sources: sources,
      includes: ['third_party/bbpPairings/src'],
      // The tournament checker and random tournament generator are test
      // tools; the app only pairs.
      defines: {
        'OMIT_GENERATOR': null,
        'OMIT_CHECKER': null,
        // trf.cpp decodes UTF-8 with std::wstring_convert, deprecated since
        // C++17; MSVC warns (and fails under /sdl) without this.
        if (windows) '_SILENCE_CXX17_CODECVT_HEADER_DEPRECATION_WARNING': null,
      },
      flags: windows
          ? ['/EHsc', '/utf-8', '/bigobj', '/permissive-']
          : ['-fvisibility=hidden', '-Wno-deprecated-declarations'],
    ).run(input: input, output: output);
  });
}
