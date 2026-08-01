import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../localization/app_localizations.dart';
import '../localization/app_locales.dart';
import '../routing/app_router.dart';
import '../routing/app_routes.dart';
import '../theme/app_theme.dart';
import 'app_config.dart';
import 'app_settings_controller.dart';

/// Root application widget. Wires theme, routing and localization together.
class LockSysHrApp extends StatefulWidget {
  const LockSysHrApp({super.key});

  @override
  State<LockSysHrApp> createState() => _LockSysHrAppState();
}

class _LockSysHrAppState extends State<LockSysHrApp> {
  final AppSettingsController _settings = AppSettingsController.instance;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: AppConfig.showDebugBanner,
          themeMode: _settings.themeMode,
          theme: AppTheme.light(arabic: _settings.isArabic),
          locale: _settings.locale,
          supportedLocales: AppLocales.supported,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          initialRoute: AppRoutes.login,
          onGenerateRoute: AppRouter.onGenerateRoute,
          builder: (context, child) {
            final mediaQueryData = MediaQuery.of(context);
            // ignore: deprecated_member_use
            return MediaQuery(
              // ignore: deprecated_member_use
              data: mediaQueryData.copyWith(
                // ignore: deprecated_member_use
                textScaleFactor: _settings.fontSizeScale,
              ),
              child: child!,
            );
          },
        );
      },
    );
  }
}
