import 'package:flutter/material.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/force_change_password_screen.dart';
import '../features/home/presentation/main_shell_screen.dart';
import '../features/trips/presentation/my_trips_screen.dart';
import 'app_routes.dart';

/// Generates routes for the app.
///
/// Feature screens are intentionally not implemented yet. Each route currently
/// resolves to a neutral placeholder; replace these mappings with real screens
/// as features are developed (splash, language, onboarding, auth, home, etc.).
class AppRouter {
  AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.login:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const LoginScreen(),
        );
      case AppRoutes.forgotPassword:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ForgotPasswordScreen(),
        );
      case AppRoutes.forceChangePassword:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ForceChangePasswordScreen(),
        );
      case AppRoutes.home:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const MainShellScreen(),
        );
      case AppRoutes.myTrips:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const MyTripsScreen(),
        );
      case AppRoutes.splash:
      case AppRoutes.language:
      case AppRoutes.onboarding:
      case AppRoutes.otp:
      case AppRoutes.notifications:
      case AppRoutes.profile:
      case AppRoutes.settings:
        return _placeholder(settings);
      default:
        return _notFound(settings);
    }
  }

  static MaterialPageRoute<dynamic> _placeholder(RouteSettings settings) {
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => _PlaceholderScreen(routeName: settings.name ?? 'unknown'),
    );
  }

  static MaterialPageRoute<dynamic> _notFound(RouteSettings settings) {
    return MaterialPageRoute(
      settings: settings,
      builder: (_) =>
          _PlaceholderScreen(routeName: 'No route for "${settings.name}"'),
    );
  }
}

/// Temporary neutral placeholder — no design. Removed as real screens land.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.routeName});

  final String routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(routeName)));
  }
}
