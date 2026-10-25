/// BBP Pairings' exit codes, kept so callers can tell "no legal pairing"
/// from a malformed file. [unavailable]: this build has no engine (the
/// browser version).
enum BbpFailureKind {
  noValidPairing,
  unexpected,
  invalidInput,
  tooLarge,
  unavailable,
}

class BbpFailure implements Exception {
  const BbpFailure(this.kind, this.message);
  final BbpFailureKind kind;
  final String message;
  @override
  String toString() => message;
}
