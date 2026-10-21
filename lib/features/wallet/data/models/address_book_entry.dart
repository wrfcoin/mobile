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

class AddressBookEntry {
  final String label;
  final String address;
  final AddressStatus status;

  /// A locally verified current address for a [AddressStatus.knownLegacy]
  /// entry. Offered for explicit selection only; never substituted.
  final String? replacementAddress;

  const AddressBookEntry({
    required this.label,
    required this.address,
    this.status = AddressStatus.unverified,
    this.replacementAddress,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'address': address,
    if (status != AddressStatus.unverified) 'status': status.name,
    if (replacementAddress != null) 'replacement': replacementAddress,
  };

  static AddressBookEntry fromJson(Map<String, dynamic> json) {
    final replacement = (json['replacement'] as String?)?.trim();
    return AddressBookEntry(
      label: (json['label'] as String? ?? '').trim(),
      address: (json['address'] as String? ?? '').trim(),
      status: AddressStatus.parse(json['status']),
      replacementAddress: replacement == null || replacement.isEmpty
          ? null
          : replacement,
    );
  }
}
