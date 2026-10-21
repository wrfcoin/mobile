enum HomeWidgetRuntimeState { implemented, hardwareDependent, unimplemented }

class HomeWidgetTransport {
  const HomeWidgetTransport({
    required this.id,
    required this.name,
    required this.runtimeState,
    required this.runtimeBoundary,
    this.supportsWeather = false,
    this.supportsPassiveBarometer = false,
  });

  final String id;
  final String name;
  final HomeWidgetRuntimeState runtimeState;
  final String runtimeBoundary;
  final bool supportsWeather;
  final bool supportsPassiveBarometer;

  bool get isRuntimeVerified =>
      runtimeState == HomeWidgetRuntimeState.implemented;

  bool get isHardwareDependent =>
      runtimeState == HomeWidgetRuntimeState.hardwareDependent;
}

class HomeWidgetTransports {
  const HomeWidgetTransports._();

  static const androidWidget = HomeWidgetTransport(
    id: 'android-widget',
    name: 'Android App Widget / Glance',
    runtimeState: HomeWidgetRuntimeState.hardwareDependent,
    supportsWeather: true,
    supportsPassiveBarometer: true,
    runtimeBoundary:
        'UNVERIFIED in this session: Android WidgetKit-equivalent runtime bridge'
        ' not available in this environment.',
  );

  static const iosWidget = HomeWidgetTransport(
    id: 'ios-widget',
    name: 'iOS WidgetKit extension',
    runtimeState: HomeWidgetRuntimeState.hardwareDependent,
    supportsWeather: true,
    supportsPassiveBarometer: true,
    runtimeBoundary:
        'UNVERIFIED in this session: iOS WidgetKit extension runtime not'
        ' connected here.',
  );

  static const webFallback = HomeWidgetTransport(
    id: 'web-fallback',
    name: 'Web/desktop fallback',
    runtimeState: HomeWidgetRuntimeState.unimplemented,
    supportsWeather: true,
    supportsPassiveBarometer: false,
    runtimeBoundary:
        'UNVERIFIED in this session: home-screen widgets are native-only; no'
        ' web or desktop transport.',
  );

  static const values = [androidWidget, iosWidget, webFallback];
}
