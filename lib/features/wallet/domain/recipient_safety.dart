import '../data/models/address_book_entry.dart';

/// What this device positively knows about a Send destination.
enum RecipientKnowledge {
  /// No local evidence. This is *not* "safe".
  unknown,

  /// Positively known legacy / receive-only alias: ordinary Send is blocked.
  knownLegacy,
}

class RecipientAssessment {
  const RecipientAssessment._(this.knowledge, this.reason, this.replacement);

  const RecipientAssessment.unknown()
    : this._(RecipientKnowledge.unknown, null, null);

  const RecipientAssessment.knownLegacy({
    required String reason,
    String? replacement,
  }) : this._(RecipientKnowledge.knownLegacy, reason, replacement);

  final RecipientKnowledge knowledge;

  /// Why Send is blocked; null when [knowledge] is [RecipientKnowledge.unknown].
  final String? reason;

  /// A locally verified current address, offered for explicit selection only.
  final String? replacement;

  bool get blocksSend => knowledge == RecipientKnowledge.knownLegacy;
}

final _hexAddress = RegExp(r'^0x[a-fA-F0-9]{40}$');

/// Signed transfers and fee estimates accept only core4 hex addresses
/// (backend `isLaunchAddress`). Shared by Send, the address book and import.
bool isSendableAddress(String value) => _hexAddress.hasMatch(value.trim());

String _norm(String value) => value.trim().toLowerCase();

/// Classifies [to] using only local knowledge:
///  * the wallet's own non-canonical (legacy/login) alias, and
///  * address-book entries explicitly marked [AddressStatus.knownLegacy].
///
/// The address text itself is never inspected for a scheme.
RecipientAssessment assessRecipient({
  required String to,
  required List<AddressBookEntry> addressBook,
  String? ownLegacyAlias,
}) {
  final target = _norm(to);
  if (target.isEmpty) return const RecipientAssessment.unknown();

  String? verifiedReplacement(String? candidate) {
    if (candidate == null) return null;
    final value = candidate.trim();
    return _hexAddress.hasMatch(value) && _norm(value) != target ? value : null;
  }

  for (final entry in addressBook) {
    if (entry.status == AddressStatus.knownLegacy &&
        _norm(entry.address) == target) {
      return RecipientAssessment.knownLegacy(
        reason:
            'This is a legacy receive-only address saved as "${entry.label}". '
            'Funds sent here cannot be spent by this wallet.',
        replacement: verifiedReplacement(entry.replacementAddress),
      );
    }
  }

  if (ownLegacyAlias != null && _norm(ownLegacyAlias) == target) {
    return const RecipientAssessment.knownLegacy(
      reason:
          'This is your own legacy receive-only address. Funds sent here '
          'cannot be spent by this wallet.',
    );
  }
  return const RecipientAssessment.unknown();
}
