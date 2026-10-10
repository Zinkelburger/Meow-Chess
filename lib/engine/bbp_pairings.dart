import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The FIDE Dutch system (C.04.3, rules effective 1 February 2026) as
/// implemented by BBP Pairings, the engine behind SwissSys's FIDE
/// endorsement. Compiled from `third_party/bbpPairings` by `hook/build.dart`.
///
/// Pure with respect to Dart state: a TRF-2026 tournament in, pairs out.
@Native<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32, Pointer<Int32>)>(
  symbol: 'meow_bbp_pair_dutch',
)
external int _pairDutch(
  Pointer<Utf8> trf,
  Pointer<Utf8> out,
  int capacity,
  Pointer<Int32> length,
);

/// BBP Pairings' exit codes, kept so callers can tell "no legal pairing"
/// from a malformed file.
enum BbpFailureKind { noValidPairing, unexpected, invalidInput, tooLarge }

class BbpFailure implements Exception {
  const BbpFailure(this.kind, this.message);
  final BbpFailureKind kind;
  final String message;
  @override
  String toString() => message;
}

/// Pairs the next round of [trf]. Returns `(white, black)` starting ranks in
/// board order; black is 0 for the pairing-allocated bye.
List<(int, int)> bbpPairDutch(String trf) {
  var capacity = 1 << 16;
  final input = trf.toNativeUtf8();
  final length = calloc<Int32>();
  try {
    while (true) {
      final out = calloc<Uint8>(capacity).cast<Utf8>();
      try {
        final code = _pairDutch(input, out, capacity, length);
        if (length.value >= capacity) {
          capacity = length.value + 1;
          continue;
        }
        final text = utf8.decode(
          out.cast<Uint8>().asTypedList(length.value),
          allowMalformed: true,
        );
        if (code != 0) {
          throw BbpFailure(switch (code) {
            1 => BbpFailureKind.noValidPairing,
            3 => BbpFailureKind.invalidInput,
            4 => BbpFailureKind.tooLarge,
            _ => BbpFailureKind.unexpected,
          }, text.trim());
        }
        return _parsePairs(text);
      } finally {
        calloc.free(out);
      }
    }
  } finally {
    calloc.free(input);
    calloc.free(length);
  }
}

/// BBP's output: the number of pairs, then one `white black` line each.
List<(int, int)> _parsePairs(String text) {
  BbpFailure malformed() => BbpFailure(
    BbpFailureKind.unexpected,
    'BBP Pairings returned an unreadable pairing: ${text.trim()}',
  );
  final lines = const LineSplitter()
      .convert(text)
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final count = lines.isEmpty ? null : int.tryParse(lines.first);
  if (count == null || lines.length <= count) throw malformed();
  return [
    for (final line in lines.skip(1).take(count))
      switch (line.split(RegExp(r'\s+')).map(int.tryParse).toList()) {
        [final int white, final int black, ...] => (white, black),
        _ => throw malformed(),
      },
  ];
}
