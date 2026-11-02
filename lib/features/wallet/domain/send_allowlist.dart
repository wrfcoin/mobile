import '../data/models/address_book_entry.dart';

/// How long a change that loosens the send allowlist waits before it applies.
const Duration sendAllowlistCooldown = Duration(hours: 24);

/// The exact help text shown wherever the allowlist is explained.
const String sendAllowlistScopeNote =
    'This protects you from mistakes in this app. For protection against a '
    'stolen phrase, see the on-chain allowlist (coming)';

/// Stored settings for the app-level send allowlist. Device-only.
class SendAllowlistSettings {
  const SendAllowlistSettings({
    this.enabled = false,
    this.turnsOffAt,
    this.unreadable = false,
  });

  static const off = SendAllowlistSettings();

  /// What a saved setting that can't be read counts as: on, with no turn-off
  /// pending, so a damaged setting never skips the 24 hour wait. Never saved:
  /// the turn-off path and "keep it on" each replace it with a real setting.
  static const unreadableOn = SendAllowlistSettings(
    enabled: true,
    unreadable: true,
  );

  /// The user turned the allowlist on (and it has not finished turning off).
  final bool enabled;

  /// A requested turn-off that applies at this time. Null: none pending.
  final DateTime? turnsOffAt;

  /// The saved setting could not be read, so this is [unreadableOn].
  final bool unreadable;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (turnsOffAt != null)
      'turns_off_at': turnsOffAt!.toUtc().millisecondsSinceEpoch,
  };

  /// Throws [FormatException] unless this is exactly what [toJson] writes: a
  /// wrong shape must not read as off.
  static SendAllowlistSettings fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'];
    final at = json['turns_off_at'];
    if (enabled is! bool || (at != null && at is! int)) {
      throw const FormatException('Invalid send allowlist settings');
    }
    return SendAllowlistSettings(
      enabled: enabled,
      turnsOffAt: at == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(at as int, isUtc: true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SendAllowlistSettings &&
      other.enabled == enabled &&
      other.turnsOffAt == turnsOffAt &&
      other.unreadable == unreadable;

  @override
  int get hashCode => Object.hash(enabled, turnsOffAt, unreadable);
}

/// Where one contact stands with the allowlist.
enum ContactAllowState { notAllowed, pending, allowed }

/// Why Send refused a recipient, or [allowed].
enum AllowlistVerdictKind { allowed, notSaved, notAllowed, pending }

class AllowlistVerdict {
  const AllowlistVerdict(
    this.kind, {
    this.contact,
    this.allowedFrom,
    this.settingsUnreadable = false,
  });

  final AllowlistVerdictKind kind;
  final AddressBookEntry? contact;

  /// For [AllowlistVerdictKind.pending]: when the contact becomes allowed.
  final DateTime? allowedFrom;

  /// Refused while the saved settings can't be read, which is why it is on.
  final bool settingsUnreadable;

  bool get blocksSend => kind != AllowlistVerdictKind.allowed;
}

/// The cooldown state machine. Pure Dart; [clock] is injectable for tests.
///
/// * Turning the allowlist on is instant. Turning it off waits
///   [sendAllowlistCooldown] and can be cancelled meanwhile.
/// * While the allowlist is on, allowing a contact waits the cooldown.
///   While it is off, allowing is instant: nothing is guarded yet.
/// * Removing an allowance or a contact is instant (it only tightens).
///
/// The times come from this phone's clock, so this is a guard against
/// mistakes and pressure from scammers, not against someone who controls
/// the phone.
class SendAllowlistPolicy {
  SendAllowlistPolicy({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  DateTime get now => _clock();

  /// Whether Send is currently restricted.
  bool isOn(SendAllowlistSettings s) {
    if (!s.enabled) return false;
    final off = s.turnsOffAt;
    return off == null || now.isBefore(off);
  }

  /// The settings with any due turn-off applied (for saving back).
  SendAllowlistSettings settle(SendAllowlistSettings s) =>
      s.enabled && !isOn(s) ? SendAllowlistSettings.off : s;

  SendAllowlistSettings turnOn(SendAllowlistSettings s) =>
      const SendAllowlistSettings(enabled: true);

  /// Starts (or keeps) a pending turn-off. A second request never pushes an
  /// earlier pending time later or earlier.
  SendAllowlistSettings requestTurnOff(SendAllowlistSettings s) {
    if (!isOn(s)) return SendAllowlistSettings.off;
    if (s.turnsOffAt != null) return s;
    return SendAllowlistSettings(
      enabled: true,
      turnsOffAt: now.add(sendAllowlistCooldown),
    );
  }

  SendAllowlistSettings cancelTurnOff(SendAllowlistSettings s) =>
      isOn(s) ? const SendAllowlistSettings(enabled: true) : s;

  /// Marks [entry] allowed: from now when the allowlist is off, after the
  /// cooldown when it is on. An existing allowance is never moved.
  AddressBookEntry allow(AddressBookEntry entry, SendAllowlistSettings s) {
    if (entry.allowedFrom != null) return entry;
    return entry.copyWith(
      allowedFrom: isOn(s) ? now.add(sendAllowlistCooldown) : now,
    );
  }

  AddressBookEntry revoke(AddressBookEntry entry) =>
      entry.copyWith(clearAllowed: true);

  ContactAllowState stateOf(AddressBookEntry entry) {
    final from = entry.allowedFrom;
    if (from == null) return ContactAllowState.notAllowed;
    return now.isBefore(from)
        ? ContactAllowState.pending
        : ContactAllowState.allowed;
  }

  /// Whether Send may go to [to] under [settings].
  AllowlistVerdict check({
    required String to,
    required List<AddressBookEntry> book,
    required SendAllowlistSettings settings,
  }) {
    if (!isOn(settings)) {
      return const AllowlistVerdict(AllowlistVerdictKind.allowed);
    }
    final target = to.trim().toLowerCase();
    AddressBookEntry? contact;
    for (final entry in book) {
      if (entry.address.trim().toLowerCase() == target) {
        contact = entry;
        break;
      }
    }
    if (contact == null) {
      return AllowlistVerdict(
        AllowlistVerdictKind.notSaved,
        settingsUnreadable: settings.unreadable,
      );
    }
    return switch (stateOf(contact)) {
      ContactAllowState.allowed => AllowlistVerdict(
        AllowlistVerdictKind.allowed,
        contact: contact,
      ),
      ContactAllowState.pending => AllowlistVerdict(
        AllowlistVerdictKind.pending,
        contact: contact,
        allowedFrom: contact.allowedFrom,
        settingsUnreadable: settings.unreadable,
      ),
      ContactAllowState.notAllowed => AllowlistVerdict(
        AllowlistVerdictKind.notAllowed,
        contact: contact,
        settingsUnreadable: settings.unreadable,
      ),
    };
  }
}
