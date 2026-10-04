import '../domain/member_observation.dart';
import '../domain/model.dart';

typedef MemberLookup = Future<MemberObservation?> Function(String memberId);

enum MemberLookupFailureKind {
  accessDenied,
  rateLimited,
  unavailable,
  notFound,
  requestRejected,
}

/// Machine-readable provider failures; user-facing wording never controls retries.
class MemberLookupFailure extends TournamentException {
  const MemberLookupFailure(this.kind, super.message, {this.statusCode});

  final MemberLookupFailureKind kind;
  final int? statusCode;

  bool get stopsBatch => switch (kind) {
    MemberLookupFailureKind.accessDenied ||
    MemberLookupFailureKind.rateLimited ||
    MemberLookupFailureKind.unavailable => true,
    MemberLookupFailureKind.notFound ||
    MemberLookupFailureKind.requestRejected => false,
  };
}

class MemberNotFound extends MemberLookupFailure {
  const MemberNotFound()
    : super(
        MemberLookupFailureKind.notFound,
        'Member ID not found. No local record was changed.',
        statusCode: 404,
      );
}
