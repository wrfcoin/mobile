/// Test fixtures only. The empty answer is the live route's real answer on
/// 2026-11-02; the loaded answer follows backend observed-verification.ts.
const emptySummary = <String, dynamic>{
  'windowDays': 30,
  'status': 'unavailable',
  'reason': 'No forecast has been scored against station readings in this window yet.',
  'counts': {'pending': 0, 'scored': 0, 'unavailable': 0},
  'variables': [
    {
      'variable': 'temperature_c',
      'chain': null,
      'vsNoaa': null,
      'vsNoaaReason': 'No scored forecast has a NOAA forecast for the same station and hour, captured before it was issued.',
    },
    {
      'variable': 'pressure_hpa',
      'chain': null,
      'vsNoaa': null,
      'vsNoaaReason': 'NOAA hourly forecasts do not include pressure.',
    },
    {
      'variable': 'humidity_pct',
      'chain': null,
      'vsNoaa': null,
      'vsNoaaReason': 'No scored forecast has a NOAA forecast for the same station and hour, captured before it was issued.',
    },
  ],
  'stations': <Object>[],
  'recent': <Object>[],
};

final loadedSummary = <String, dynamic>{
  'windowDays': 30,
  'status': 'available',
  'reason': null,
  'counts': {'pending': 2, 'scored': 1234, 'unavailable': 1},
  'variables': [
    {
      'variable': 'temperature_c',
      'chain': {'n': 1234, 'mae': 0.8125, 'bias': -0.25, 'rmse': 1.1},
      'vsNoaa': {
        'n': 900,
        'chainMae': 0.75,
        'noaaMae': 1.5,
        'chainBias': -0.2,
        'noaaBias': 0.4,
      },
      'vsNoaaReason': null,
    },
    {
      'variable': 'pressure_hpa',
      'chain': {'n': 40, 'mae': 1.5, 'bias': 0.5, 'rmse': 2.0},
      'vsNoaa': null,
      'vsNoaaReason': 'NOAA hourly forecasts do not include pressure.',
    },
  ],
  'stations': [
    {'stationAlias': 'quiet-otter', 'scored': 1234},
  ],
  'recent': [
    {
      'commitId': 'a' * 64,
      'stationAlias': 'quiet-otter',
      'modelId': 'kit-persistence-v1',
      'validAt': '2026-11-01T18:00:00.000Z',
      'status': 'scored',
      'unavailableReason': null,
      'forecast': {'temperature_c': 21.5},
      'scores': {
        'temperature_c': {
          'forecast': 21.5,
          'truth': 21.0,
          'error': 0.5,
          'noaa': {'value': 23.0, 'error': 2.0, 'leadHours': 6},
        },
      },
      'noaaReason': null,
    },
    {
      'commitId': 'b' * 64,
      'stationAlias': 'still-heron',
      'modelId': null,
      'validAt': '2026-11-02T06:00:00.000Z',
      'status': 'pending',
      'unavailableReason': null,
      'forecast': {'pressure_hpa': 1012.5},
      'scores': null,
      'noaaReason': null,
    },
    {
      'commitId': 'c' * 64,
      'stationAlias': 'quiet-otter',
      'modelId': 'kit-persistence-v1',
      'validAt': '2026-10-31T06:00:00.000Z',
      'status': 'unavailable',
      'unavailableReason': 'no_chain_reading_in_target_hour',
      'forecast': {'temperature_c': 18.0},
      'scores': null,
      'noaaReason': null,
    },
  ],
};
