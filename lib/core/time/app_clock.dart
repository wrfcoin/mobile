import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The time, replaceable in tests that are about data getting old.
final appClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
