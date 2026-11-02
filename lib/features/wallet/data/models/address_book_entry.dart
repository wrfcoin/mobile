/// What this device positively knows about a saved destination.
///
/// Nothing here is derived from the address text: a status other than
/// [unverified] only comes from a stored value or from the wallet's own
/// local identity. [unverified] means "unknown", never "safe".
enum AddressStatus {
  /// No local evidence either way (all entries saved before this field).
  unverified,

  /// Explicitly marked as a legacy, receive-only alias.
  knownLegacy,

  /// Explicitly marked as a verified current (spendable) address.
  verifiedCurrent;

  static AddressStatus parse(Object? raw) {
    for (final status in values) {
      if (status.name == raw) return status;
    }
    return unverified;
  }
}

/// A saved contact. Stored only on this device (flutter_secure_storage); it
/// is never sent to a server. The only personal field is a name the user
/// chooses.
class AddressBookEntry {
  final String label;
  final String address;
  final AddressStatus status;

  /// A locally verified current address for a [AddressStatus.knownLegacy]
  /// entry. Offered for explicit selection only; never substituted.
  final String? replacementAddress;

  /// When this contact is (or becomes) allowed by the send allowlist.
  /// Null: not allowed. A time in the future: allowed after a cooldown.
  final DateTime? allowedFrom;

  const AddressBookEntry({
    required this.label,
    required this.address,
    this.status = AddressStatus.unverified,
    this.replacementAddress,
    this.allowedFrom,
  });

  AddressBookEntry copyWith({
    String? label,
    DateTime? allowedFrom,
    bool clearAllowed = false,
  }) {
    return AddressBookEntry(
      label: label ?? this.label,
      address: address,
      status: status,
      replacementAddress: replacementAddress,
      allowedFrom: clearAllowed ? null : (allowedFrom ?? this.allowedFrom),
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'address': address,
    if (status != AddressStatus.unverified) 'status': status.name,
    if (replacementAddress != null) 'replacement': replacementAddress,
    if (allowedFrom != null)
      'allowed_from': allowedFrom!.toUtc().millisecondsSinceEpoch,
  };

  static AddressBookEntry fromJson(Map<String, dynamic> json) {
    final replacement = (json['replacement'] as String?)?.trim();
    final allowedFrom = json['allowed_from'];
    return AddressBookEntry(
      label: (json['label'] as String? ?? '').trim(),
      address: (json['address'] as String? ?? '').trim(),
      status: AddressStatus.parse(json['status']),
      replacementAddress: replacement == null || replacement.isEmpty
          ? null
          : replacement,
      allowedFrom: allowedFrom is int
          ? DateTime.fromMillisecondsSinceEpoch(allowedFrom, isUtc: true)
          : null,
    );
  }
}
