import 'package:dio/dio.dart';

/// On web, no custom adapter is needed — cert pinning is browser-managed.
HttpClientAdapter? createPinnedAdapter() => null;
