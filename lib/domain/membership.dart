import 'model.dart';
import 'us_chess.dart';

/// A dated observation, never an assumption that a player is eligible to play.
/// [eventDate] is the event's last day. Once it has passed, expiry is judged
/// against it, so reviewing a past event flags only lapses that mattered then.
class MembershipSummary {
  MembershipSummary(Player player, {required String eventDate, DateTime? now}) {
    final evidence = player.membershipEvidence;
    if (!isMemberId(player.memberId)) {
      label = 'No USCF ID';
      detail = 'Enter a US Chess ID, then check membership.';
      return;
    }
    if (evidence['id'] != player.memberId || evidence['retrievedAt'] == null) {
      label = 'Not checked';
      detail = 'Check membership to fetch the expiration date from US Chess.';
      return;
    }
    final expiration = evidence['expiration'];
    final status = evidence['status'] as String?;
    final validDate = expiration is String && isEventDate(expiration);
    final today = (now ?? DateTime.now()).toIso8601String().substring(0, 10);
    final past = isEventDate(eventDate) && eventDate.compareTo(today) < 0;
    final expired =
        validDate && expiration.compareTo(past ? eventDate : today) < 0;
    final expiresBeforeEvent =
        validDate &&
        !past &&
        isEventDate(eventDate) &&
        expiration.compareTo(eventDate) < 0;
    final expiringThisMonth =
        validDate &&
        !expired &&
        !past &&
        expiration.substring(0, 7) == today.substring(0, 7);
    final inactive = status != null && status.toLowerCase() != 'active';
    severity = expired || inactive
        ? MembershipSeverity.error
        : expiringThisMonth || expiresBeforeEvent
        ? MembershipSeverity.warning
        : MembershipSeverity.normal;
    warning = expired
        ? past
              ? 'Expired before event ended'
              : 'Expired'
        : inactive
        ? 'Status: $status'
        : expiringThisMonth
        ? 'Expires this month'
        : expiresBeforeEvent
        ? 'Expires before event ends'
        : null;
    label = validDate ? expiration : 'Date unavailable';
    detail = [
      validDate
          ? 'Expires $expiration.'
          : 'US Chess returned no readable expiration date.',
      if (expired)
        past
            ? 'Expired before the event ended ($eventDate).'
            : 'Expired as of today.',
      if (expiringThisMonth) 'Expires this month.',
      if (expiresBeforeEvent) 'Expires before the event ends ($eventDate).',
      'Membership status: ${status ?? 'unknown'}.',
      'Checked ${evidence['retrievedAt']} · ${evidence['provider'] ?? 'US Chess'}.',
    ].join('\n');
  }

  late final String label, detail;
  MembershipSeverity severity = MembershipSeverity.normal;
  bool get attention => severity != MembershipSeverity.normal;
  String? warning;
}

enum MembershipSeverity { normal, warning, error }
