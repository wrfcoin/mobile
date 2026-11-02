/// `GET /weather/leaderboard?metric=earnings`, with the shape and amounts of the
/// live answer on 2026-11-02 (backend `weather-leaderboard-routes.ts`).
Map<String, dynamic> weatherBoard({
  String period = 'all',
  bool ownRow = false,
}) {
  Map<String, dynamic> row(
    int rank,
    String address,
    String key,
    String name,
    String baseUnits,
    String wrf, {
    bool isYou = false,
  }) => <String, dynamic>{
    'rank': rank,
    'walletAddress': address,
    'profileKey': key,
    'isYou': isYou,
    'displayName': name,
    'value': double.parse(wrf),
    'badgeLevel': 'gold',
    'streak': null,
    'country': null,
    'city': null,
    'earningsBaseUnits': baseUnits,
    'earningsWrf': wrf,
  };

  return <String, dynamic>{
    'success': true,
    'metric': 'earnings',
    'period': period,
    'country': null,
    'region': null,
    'near': null,
    'updatedAt': '2026-11-02T02:30:52.537Z',
    'earningsScope': 'lifetime',
    'earningsDescription': 'Lifetime real-station rewards paid to the address (node-proven). The period filter ranks only; it does not window this amount.',
    'amountUnits': <String, dynamic>{
      'denomination': 'WRF',
      'baseUnitDecimals': 8,
      'baseUnitsPerUnit': '100000000',
      'available': true,
      'fields': <String, dynamic>{
        'entries[].earningsBaseUnits': 'base_units',
        'entries[].earningsWrf': 'display_units',
      },
    },
    'entries': <Map<String, dynamic>>[
      row(
        1,
        '0x1747…a275',
        'c_96a7e35eb194a29550917a4f',
        'WeatherNode-1747C0',
        '188795124509',
        '1887.95124509',
      ),
      row(
        2,
        ownRow ? '0x7d29a40000000000000000000000000000000cb2' : '0x7d29…0cb2',
        'c_9649ba143a37dd220c1df06a',
        'WeatherNode-7D29A4',
        '121547812500',
        '1215.478125',
        isYou: ownRow,
      ),
      row(
        3,
        '0x3dc6…e37c',
        'c_53c41ae756ebac9b7c16f029',
        'WeatherNode-3DC67F',
        '452812500',
        '4.528125',
      ),
    ],
  };
}
