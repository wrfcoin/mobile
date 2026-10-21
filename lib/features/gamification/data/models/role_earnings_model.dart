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
  const RolePaidSummary(this.role, this.status, this.amount, this.coverage);
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
  String get message => switch (status) {
    EarningsStatus.available => '$amount WRF',
    EarningsStatus.unsupported => 'Node payments are not implemented yet',
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
}

class RoleLeaderboard {
  final EarningsRole role;
  final EarningsPeriod period;
  final EarningsStatus status;
  final List<RoleEarningsRow> rows;
  final EarningsCoverage? coverage;
  const RoleLeaderboard(
    this.role,
    this.period,
    this.status,
    this.rows,
    this.coverage,
  );
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
  final EarningsCoverage coverage;
  const OwnRoleEarnings(this.roles, this.coverage);
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
