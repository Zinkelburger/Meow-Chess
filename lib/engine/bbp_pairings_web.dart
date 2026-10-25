import 'bbp_failure.dart';

export 'bbp_failure.dart';

/// The browser version cannot run the FIDE Dutch engine yet.
List<(int, int)> bbpPairDutch(String trf) => throw const BbpFailure(
  BbpFailureKind.unavailable,
  'FIDE Dutch pairings need the Meow-Chess desktop app. Pair this round by hand, or open the event in the desktop app.',
);
