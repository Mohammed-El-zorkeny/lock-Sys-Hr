import 'package:flutter/foundation.dart';

enum AppEnvironment { development, staging, production }

/// App-wide general configuration. No business logic — config values only.
class AppConfig {
  AppConfig._();

  static const String appName = 'LockSys HR';
  static const String appVersion = '1.0.0';
  static const String baseUrl = 'https://api.locksys.co/ords/locksysapp';

  static const AppEnvironment environment = AppEnvironment.development;

  static bool get isDebug => kDebugMode;
  static bool get isProduction => environment == AppEnvironment.production;

  /// Always false in release; toggles debug-only banners/tools.
  static const bool showDebugBanner = false;
}
