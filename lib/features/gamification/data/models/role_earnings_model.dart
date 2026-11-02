enum EarningsRole {
  contribution('Weather data'),
  attester('Oracles & attesters'),
  producer('Block producers'),
  node('Nodes'),
  forecast('Forecasting');

  const EarningsRole(this.label);
  final String label;
}

enum EarningsPeriod {
  all('All time'),
  sevenDays('7 days'),
  thirtyDays('30 days');

  const EarningsPeriod(this.label);
  final String label;
  String get wire => switch (this) {
    all => 'all',
    sevenDays => '7d',
    thirtyDays => '30d',
  };
}

enum EarningsStatus { available, unsupported, unavailable }

/// The backend still answers `unsupported` for the node role because it has no
/// node board. That is not the same as nodes going unpaid, so the phone does
/// not repeat "not implemented": bonded nodes are paid.
const String kNodePaymentsNotice =
    'Bonded nodes are paid. This list does not show node payments yet.';

Map<String, dynamic> object(dynamic value) {
  if (value is! Map) throw const FormatException('Invalid earnings contract');
  return Map<String, dynamic>.from(value);
}

String text(dynamic value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Missing earnings metadata');
  }
  return value;
}

String integer(dynamic value) {
  final s = text(value);
  if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(s)) {
    throw const FormatException('Invalid amount');
  }
  return s;
}

String paidDisplay(dynamic value) {
  final n = BigInt.parse(integer(value));
  final scale = BigInt.from(100000000);
  return '${n ~/ scale}.${(n % scale).toString().padLeft(8, '0')}';
}

void validateUnits(dynamic value) {
  final u = object(value);
  if (u['currency'] != 'WRF' ||
      u['decimals'] != 8 ||
      u['scale'] != '100000000') {
    throw const FormatException('Unknown earnings units');
  }
}

class EarningsCoverage {
  final String fromHeight, throughHeight, hash, time;
  const EarningsCoverage(
    this.fromHeight,
    this.throughHeight,
    this.hash,
    this.time,
  );
  factory EarningsCoverage.parse(dynamic coverage, dynamic asOf) {
    final c = object(coverage), a = object(asOf);
    final from = integer(c['fromHeight']),
        through = integer(c['throughHeight']);
    final hash = text(a['hash']), time = text(a['time']);
    if (c['complete'] != true ||
        from != '1' ||
        BigInt.parse(through) < BigInt.one ||
        a['height'] != through ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        DateTime.tryParse(time) == null ||
        DateTime.tryParse(text(a['checkedAt'])) == null) {
      throw const FormatException('Incomplete earnings coverage');
    }
    return EarningsCoverage(from, through, hash, time);
  }
  String get label => 'Through height $throughHeight · $time';
}

class RolePaidSummary {
  final EarningsRole role;
  final EarningsStatus status;
  final String? amount;
  final EarningsCoverage? coverage;

  /// Replaces the status wording when the phone knows something more exact.
  final String? note;
  const RolePaidSummary(
    this.role,
    this.status,
    this.amount,
    this.coverage, {
    this.note,
  });
  factory RolePaidSummary.parse(Map<String, dynamic> j, EarningsRole role) {
    if (j['role'] != role.name) throw const FormatException('Role mismatch');
    final status = EarningsStatus.values.byName(text(j['status']));
    if (status == EarningsStatus.available) {
      if (j['complete'] != true ||
          j['paidDisplay'] != paidDisplay(j['paidBaseUnits'])) {
        throw const FormatException('Invalid paid total');
      }
      return RolePaidSummary(
        role,
        status,
        paidDisplay(j['paidBaseUnits']),
        EarningsCoverage.parse(j['coverage'], j['asOf']),
      );
    }
    if (j['paidBaseUnits'] != null ||
        j['complete'] != false ||
        (status == EarningsStatus.unsupported && role != EarningsRole.node)) {
      throw const FormatException('Unproven total');
    }
    return RolePaidSummary(role, status, null, null);
  }
  String get message =>
      note ??
      switch (status) {
        EarningsStatus.available => '$amount WRF',
        EarningsStatus.unsupported => kNodePaymentsNotice,
        EarningsStatus.unavailable => 'Paid-event coverage unavailable',
      };
}

class RoleEarningsRow {
  final int rank;
  final String profileKey, shortAddress, displayName, amount;
  final bool isYou;
  const RoleEarningsRow(
    this.rank,
    this.profileKey,
    this.shortAddress,
    this.displayName,
    this.amount,
    this.isYou,
  );
  factory RoleEarningsRow.parse(dynamic value) {
    final j = object(value);
    final key = text(j['profileKey']),
        address = text(j['shortAddress']),
        name = text(j['displayName']);
    final amount = paidDisplay(j['paidBaseUnits']);
    if (j['rank'] is! int ||
        j['rank'] < 1 ||
        !RegExp(r'^c_[0-9a-f]{24}$').hasMatch(key) ||
        !RegExp(r'^0x[0-9a-fA-F]{4}…[0-9a-fA-F]{4}$').hasMatch(address) ||
        RegExp(r'0x[0-9a-fA-F]{40}|[0-9a-fA-F]{64}').hasMatch(name) ||
        j['paidDisplay'] != amount ||
        j['isYou'] is! bool) {
      throw const FormatException('Invalid public earnings row');
    }
    return RoleEarningsRow(j['rank'], key, address, name, amount, j['isYou']);
  }

  /// One row of `GET /weather/leaderboard?metric=earnings`.
  ///
  /// The amount comes from the exact `earningsBaseUnits` string, never from the
  /// `value` double. A row that cannot be proven fails the whole board. The
  /// address is shown as served: short, except on the viewer's own row.
  factory RoleEarningsRow.parseWeather(dynamic value) {
    final j = object(value);
    final rank = j['rank'], isYou = j['isYou'], key = j['profileKey'];
    final address = text(j['walletAddress']), name = text(j['displayName']);
    final amount = paidDisplay(j['earningsBaseUnits']);
    final shortForm = RegExp(r'^[0-9a-zA-Z]{6}…[0-9a-fA-F]{4}$');
    final fullForm = RegExp(r'^(0x|wrf)[0-9a-fA-F]{40}$');
    if (rank is! int ||
        rank < 1 ||
        isYou is! bool ||
        (key != null &&
            (key is! String || !RegExp(r'^c_[0-9a-f]{24}$').hasMatch(key))) ||
        !(shortForm.hasMatch(address) ||
            (isYou && fullForm.hasMatch(address))) ||
        RegExp(r'0x[0-9a-fA-F]{40}|[0-9a-fA-F]{64}').hasMatch(name) ||
        !_sameWrfAmount(j['earningsWrf'], amount)) {
      throw const FormatException('Invalid weather earnings row');
    }
    return RoleEarningsRow(
      rank,
      key as String? ?? '',
      address,
      name,
      amount,
      isYou,
    );
  }

  /// `earningsWrf` drops trailing zeros; [exact] always has eight decimals.
  static bool _sameWrfAmount(dynamic served, String exact) {
    if (served is! String ||
        !RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,8})?$').hasMatch(served)) {
      return false;
    }
    final parts = served.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    return '${parts[0]}.${fraction.padRight(8, '0')}' == exact;
  }
}

class RoleLeaderboard {
  final EarningsRole role;
  final EarningsPeriod period;
  final EarningsStatus status;
  final List<RoleEarningsRow> rows;
  final EarningsCoverage? coverage;

  /// True when each amount is a lifetime total and [period] only ranks rows,
  /// so the screen must not present the amount as earned in that period.
  final bool lifetimeAmounts;
  const RoleLeaderboard(
    this.role,
    this.period,
    this.status,
    this.rows,
    this.coverage, {
    this.lifetimeAmounts = false,
  });

  /// The Weather data tab, from `GET /weather/leaderboard?metric=earnings`.
  ///
  /// All or nothing, like the web: an `unavailable` marker or any contract
  /// mismatch throws, so a short list can never look complete. Only a clean
  /// answer with no entries is an empty board.
  factory RoleLeaderboard.parseWeather(dynamic value, EarningsPeriod period) {
    final j = object(value);
    final units = object(j['amountUnits']);
    final fields = object(units['fields']);
    final unavailable = j['unavailable'];
    if (j['success'] != true ||
        j['metric'] != 'earnings' ||
        j['period'] != period.wire ||
        j['earningsScope'] != 'lifetime' ||
        (unavailable is List && unavailable.isNotEmpty) ||
        units['denomination'] != 'WRF' ||
        units['baseUnitDecimals'] != 8 ||
        units['baseUnitsPerUnit'] != '100000000' ||
        units['available'] != true ||
        fields['entries[].earningsBaseUnits'] != 'base_units' ||
        fields['entries[].earningsWrf'] != 'display_units' ||
        j['entries'] is! List) {
      throw const FormatException('Weather earnings unavailable');
    }
    final rows = (j['entries'] as List)
        .map(RoleEarningsRow.parseWeather)
        .toList();
    final keys = rows.map((r) => r.profileKey).where((k) => k.isNotEmpty);
    if (rows.length > 30 ||
        keys.toSet().length != keys.length ||
        rows.indexed.any((r) => r.$2.rank != r.$1 + 1)) {
      throw const FormatException('Invalid ranking');
    }
    return RoleLeaderboard(
      EarningsRole.contribution,
      period,
      EarningsStatus.available,
      List.unmodifiable(rows),
      null,
      lifetimeAmounts: true,
    );
  }
  factory RoleLeaderboard.parse(
    dynamic value,
    EarningsRole role,
    EarningsPeriod period,
  ) {
    final j = object(value);
    validateUnits(j['units']);
    if (j['success'] != true ||
        j['role'] != role.name ||
        j['requestedScope'] != period.wire ||
        j['rows'] is! List) {
      throw const FormatException('Invalid leaderboard envelope');
    }
    final status = EarningsStatus.values.byName(text(j['status']));
    if (status != EarningsStatus.available) {
      if ((j['rows'] as List).isNotEmpty ||
          j['complete'] != false ||
          j['paidBaseUnits'] != null ||
          j['effectiveScope'] != null ||
          (status == EarningsStatus.unsupported && role != EarningsRole.node)) {
        throw const FormatException('Partial leaderboard');
      }
      return RoleLeaderboard(role, period, status, const [], null);
    }
    if (j['complete'] != true ||
        j['effectiveScope'] != period.wire ||
        j['finalityPolicy'] != 'confirmed-canonical-with-rollback') {
      throw const FormatException('Unproven leaderboard scope');
    }
    final coverage = EarningsCoverage.parse(j['coverage'], j['asOf']);
    final window = object(j['window']);
    if (window['through'] != coverage.time ||
        (period == EarningsPeriod.all
            ? window['from'] != null
            : DateTime.tryParse(text(window['from'])) == null)) {
      throw const FormatException('Invalid payment window');
    }
    if (period != EarningsPeriod.all) {
      final start = DateTime.parse(text(window['from']));
      final end = DateTime.parse(coverage.time);
      if (end.difference(start) !=
          Duration(days: period == EarningsPeriod.sevenDays ? 7 : 30)) {
        throw const FormatException('Incorrect payment window');
      }
    }
    final rows = (j['rows'] as List).map(RoleEarningsRow.parse).toList();
    if (rows.length > 30 ||
        rows.map((r) => r.profileKey).toSet().length != rows.length ||
        rows.indexed.any((r) => r.$2.rank != r.$1 + 1)) {
      throw const FormatException('Invalid ranking');
    }
    return RoleLeaderboard(
      role,
      period,
      status,
      List.unmodifiable(rows),
      coverage,
    );
  }
}

class OwnRoleEarnings {
  final List<RolePaidSummary> roles;

  /// Null when only the weather board could be read.
  final EarningsCoverage? coverage;
  const OwnRoleEarnings(this.roles, this.coverage);

  /// The viewer's figures from what the public edge admits.
  ///
  /// [profile] is the role profile, when it could be read. [weatherRow] is the
  /// viewer's row on the weather board: the profile has no weather figure, so
  /// that row supplies it, as a lifetime amount. [weatherBoardRead] says the
  /// board answered, so a missing row means only that the viewer isn't on it.
  factory OwnRoleEarnings.combine({
    OwnRoleEarnings? profile,
    RoleEarningsRow? weatherRow,
    required bool weatherBoardRead,
  }) {
    RolePaidSummary forRole(EarningsRole role) {
      if (role == EarningsRole.contribution) {
        if (weatherRow != null) {
          return RolePaidSummary(
            role,
            EarningsStatus.available,
            weatherRow.amount,
            null,
            note: '${weatherRow.amount} WRF (lifetime station rewards)',
          );
        }
        if (weatherBoardRead) {
          return RolePaidSummary(
            role,
            EarningsStatus.unavailable,
            null,
            null,
            note: 'Not among the top 30 weather earners',
          );
        }
      }
      return profile?.roles.firstWhere((r) => r.role == role) ??
          RolePaidSummary(
            role,
            role == EarningsRole.node
                ? EarningsStatus.unsupported
                : EarningsStatus.unavailable,
            null,
            null,
          );
    }

    return OwnRoleEarnings(
      List.unmodifiable(EarningsRole.values.map(forRole)),
      profile?.coverage,
    );
  }
  factory OwnRoleEarnings.parse(dynamic value) {
    final j = object(value), p = object(j['profile']);
    // Use server-authenticated ownership, never a matching label/address.
    if (j['success'] != true || p['isYou'] != true) {
      throw const FormatException('Ownership unavailable');
    }
    final earnings = object(p['roleEarnings']);
    validateUnits(earnings['units']);
    if (earnings['overallComplete'] != false ||
        earnings['overallPaidBaseUnits'] != null ||
        earnings['finalityPolicy'] != 'confirmed-canonical-with-rollback') {
      throw const FormatException('Invalid profile envelope');
    }
    final coverage = EarningsCoverage.parse(
      earnings['coverage'],
      earnings['asOf'],
    );
    final roles = object(earnings['roles']);
    return OwnRoleEarnings(
      List.unmodifiable(
        EarningsRole.values.map(
          (role) => RolePaidSummary.parse(object(roles[role.name]), role),
        ),
      ),
      coverage,
    );
  }
}
