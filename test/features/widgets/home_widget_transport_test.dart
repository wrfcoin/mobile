import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/features/widgets/domain/home_widget_transport.dart';

void main() {
  test('exposes explicit runtime boundaries for widget transports', () {
    expect(HomeWidgetTransports.values.length, 3);
    expect(
      HomeWidgetTransports.values
          .every((transport) => transport.runtimeBoundary.isNotEmpty),
      isTrue,
    );
    expect(
      HomeWidgetTransports.values
          .where((transport) => transport.isHardwareDependent)
          .map((transport) => transport.runtimeBoundary.contains('UNVERIFIED')),
      everyElement(isTrue),
    );
  });

  test('distinguishes hardware-dependent from unimplemented widget transports', () {
    expect(HomeWidgetTransports.androidWidget.isHardwareDependent, isTrue);
    expect(HomeWidgetTransports.iosWidget.isHardwareDependent, isTrue);
    expect(HomeWidgetTransports.webFallback.isRuntimeVerified, isFalse);
  });
}
