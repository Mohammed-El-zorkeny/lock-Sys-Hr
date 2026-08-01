import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../constants/asset_paths.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimensions.dart';
import '../../../routing/app_routes.dart';
import '../../../app/app_config.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/services/fcm_token_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/device_security_helper.dart';

/// Login Screen (UI & API wiring).
///
/// Arabic, RTL, Corporate Clean style. Integrates with the backend login API.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    final loggedIn = await AuthStorage.isLoggedIn();
    if (loggedIn) {
      final token = await AuthStorage.getToken();
      final phone = await AuthStorage.getPhone();
      final userData = await AuthStorage.getUserData();
      final isForceChange = userData != null &&
          (userData['isChangePassword'] == 1 || userData['isChangePassword'] == true);

      if (token != null && token.isNotEmpty) {
        if (isForceChange) {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed(AppRoutes.forceChangePassword);
          }
          return;
        }

        unawaited(FcmTokenService.updateDeviceToken(
          jwtToken: token,
          phoneNumber: phone,
        ));
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
        }
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    if (username.isEmpty || password.isEmpty) {
      _showErrorSnackBar(
        isArabic
            ? 'اسم المستخدم وكلمة المرور مطلوبان'
            : 'Username and password are required',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final deviceUuid = await DeviceSecurityHelper.getDeviceUuid();
      final url = '${AppConfig.baseUrl}/Users/LoginUser';
      final response = await ApiClient.post(
        url,
        body: {
          'username': username,
          'password': password,
          'deviceUuid': deviceUuid,
        },
      );

      final responseBody = jsonDecode(response.body);

      if (response.statusCode == 200 && responseBody['status'] == 'success') {
        final token = responseBody['token']?.toString() ?? '';
        final user = responseBody['user'] as Map<String, dynamic>;
        final phone = user['phone']?.toString() ?? '';

        final isForceChange = responseBody['isChangePassword'] == 1 || responseBody['isChangePassword'] == true;

        // Save session locally
        await AuthStorage.saveSession(token: token, user: user);

        // Update FCM Device Token in the background
        unawaited(FcmTokenService.updateDeviceToken(
          jwtToken: token,
          phoneNumber: phone,
        ));

        if (mounted) {
          if (isForceChange) {
            Navigator.of(context).pushReplacementNamed(AppRoutes.forceChangePassword);
          } else {
            // Navigate to Home screen (represented by Bottom Nav Shell)
            Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
          }
        }
      } else {
        // Handle API custom error payload
        final String errorAr = responseBody['messageAr'] ?? 'فشل تسجيل الدخول';
        final String errorEn = responseBody['messageEn'] ?? 'Login failed';
        _showErrorSnackBar(isArabic ? errorAr : errorEn);
      }
    } on TimeoutException {
      _showErrorSnackBar(
        isArabic
            ? 'انتهت مهلة الاتصال بالخادم. يرجى المحاولة لاحقاً.'
            : 'Connection timed out. Please try again later.',
      );
    } catch (e) {
      _showErrorSnackBar(
        isArabic
            ? 'حدث خطأ أثناء الاتصال بالخادم'
            : 'An error occurred while connecting to the server',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spaceLg,
                  vertical: AppDimensions.spaceLg,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        constraints.maxHeight - (AppDimensions.spaceLg * 2),
                    maxWidth: 480,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BrandMark(),
                        const SizedBox(height: AppDimensions.spaceLg),
                        const _Header(),
                        const SizedBox(height: AppDimensions.spaceLg),
                        _SoftCard(
                          child: _UsernameLoginForm(
                            usernameController: _usernameController,
                            passwordController: _passwordController,
                            obscurePassword: _obscurePassword,
                            isLoading: _isLoading,
                            onToggleObscure: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            onLoginPressed: _handleLogin,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.spaceLg),
                        const _ContactUs(),
                        const Spacer(),
                        const SizedBox(height: AppDimensions.spaceLg),
                        const _DeveloperBranding(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}


/// Form inputs and button for username and password login.
class _UsernameLoginForm extends StatelessWidget {
  const _UsernameLoginForm({
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.isLoading,
    required this.onLoginPressed,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final bool isLoading;
  final VoidCallback onLoginPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: usernameController,
          enabled: !isLoading,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'اسم المستخدم',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: AppDimensions.spaceMd),
        TextField(
          controller: passwordController,
          enabled: !isLoading,
          obscureText: obscurePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onLoginPressed(),
          decoration: InputDecoration(
            hintText: 'كلمة السر',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              onPressed: onToggleObscure,
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppDimensions.spaceSm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: isLoading
                ? null
                : () {
                    Navigator.of(context).pushNamed(AppRoutes.forgotPassword);
                  },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: AppColors.primary,
            ),
            child: const Text(
              'هل نسيت كلمة السر؟',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: AppDimensions.spaceLg),
        ElevatedButton(
          onPressed: isLoading ? null : onLoginPressed,
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.login_rounded, size: AppDimensions.iconMd),
                    SizedBox(width: AppDimensions.spaceSm),
                    Flexible(
                      child: Text(
                        'تسجيل الدخول',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Small brand badge at the top (app's own lock mark, not the developer logo).
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        ),
        child: const Icon(
          Icons.lock_outline_rounded,
          color: AppColors.primary,
          size: AppDimensions.iconLg,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'تسجيل الدخول',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDimensions.spaceSm),
        Text(
          'يرجى تسجيل الدخول للوصول إلى حسابك ومتابعة خدماتك',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _ContactUs extends StatelessWidget {
  const _ContactUs();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () {},
        icon: const Icon(
          Icons.support_agent_rounded,
          size: AppDimensions.iconMd,
        ),
        label: const Text('تواصل معنا'),
        style: TextButton.styleFrom(foregroundColor: AppColors.secondary),
      ),
    );
  }
}

class _DeveloperBranding extends StatelessWidget {
  const _DeveloperBranding();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'تم تطوير التطبيق بواسطة',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppDimensions.spaceSm),
        Image.asset(
          AssetPaths.companyLogo,
          height: 28,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Text(
            'Lock Sys',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// White rounded card with a soft (not heavy) shadow.
class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spaceLg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
