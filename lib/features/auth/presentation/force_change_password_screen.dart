import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../app/app_config.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/network/api_client.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimensions.dart';

/// Screen displayed when the user is forced to change their password on login.
class ForceChangePasswordScreen extends StatefulWidget {
  const ForceChangePasswordScreen({super.key});

  @override
  State<ForceChangePasswordScreen> createState() => _ForceChangePasswordScreenState();
}

class _ForceChangePasswordScreenState extends State<ForceChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleChangePassword() async {
    if (!_formKey.currentState!.validate()) return;

    final oldPwd = _oldPasswordController.text.trim();
    final newPwd = _newPasswordController.text.trim();
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    setState(() {
      _isLoading = true;
    });

    try {
      final token = await AuthStorage.getToken();
      if (token == null) {
        _showErrorSnackBar(isArabic ? 'انتهت جلستك. سجل الدخول مجدداً' : 'Session expired. Please login again');
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(AppRoutes.login);
        }
        return;
      }

      final url = '${AppConfig.baseUrl}/Users/ChangePassword';
      final response = await ApiClient.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: {
          'oldPassword': oldPwd,
          'newPassword': newPwd,
        },
      ).timeout(const Duration(seconds: 10));

      final responseBody = jsonDecode(response.body);

      if (response.statusCode == 200 && responseBody['status'] == 'success') {
        // Clear force change password flag locally
        await AuthStorage.clearChangePasswordFlag();

        _showSuccessSnackBar(
          isArabic
              ? 'تم تغيير كلمة المرور بنجاح. يتم تحويلك الآن...'
              : 'Password changed successfully. Redirecting...',
        );
        
        // Wait briefly for the snackbar, then navigate to Home
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
        }
      } else {
        final errorAr = responseBody['messageAr'] ?? 'فشل تغيير كلمة المرور';
        final errorEn = responseBody['messageEn'] ?? 'Failed to change password';
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
            ? 'حدث خطأ غير متوقع أثناء الاتصال بالخادم'
            : 'An unexpected error occurred while connecting to the server',
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

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return PopScope(
      canPop: false, // Prevent physical back button from bypassing this screen
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(isArabic ? 'تغيير كلمة المرور الإجباري' : 'Force Change Password'),
            centerTitle: true,
            automaticallyImplyLeading: false, // Prevent returning to login screen via back arrow
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppDimensions.spaceLg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Card Info
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.security_rounded, color: AppColors.warning, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isArabic ? 'تنبيه أمان إجباري' : 'Mandatory Security Alert',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isArabic
                                        ? 'يتطلب النظام تغيير كلمة المرور المؤقتة فوراً لتأمين حسابك قبل استخدام التطبيق.'
                                        : 'The system requires changing your temporary password immediately to secure your account before using the app.',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      height: 1.6,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Form Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Old Password Field
                              Text(
                                isArabic ? 'كلمة المرور الحالية' : 'Current Password',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _oldPasswordController,
                                obscureText: _obscureOld,
                                enabled: !_isLoading,
                                decoration: InputDecoration(
                                  hintText: isArabic ? 'أدخل كلمة المرور الحالية' : 'Enter current password',
                                  prefixIcon: const Icon(Icons.lock_open_rounded),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureOld ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(() => _obscureOld = !_obscureOld),
                                  ),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return isArabic ? 'يرجى إدخال كلمة المرور الحالية' : 'Current password is required';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              // New Password Field
                              Text(
                                isArabic ? 'كلمة المرور الجديدة' : 'New Password',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _newPasswordController,
                                obscureText: _obscureNew,
                                enabled: !_isLoading,
                                decoration: InputDecoration(
                                  hintText: isArabic ? 'أدخل كلمة المرور الجديدة' : 'Enter new password',
                                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureNew ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                                  ),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return isArabic ? 'يرجى إدخال كلمة المرور الجديدة' : 'New password is required';
                                  }
                                  if (val.trim().length < 6) {
                                    return isArabic ? 'كلمة المرور يجب ألا تقل عن 6 أحرف' : 'Password must be at least 6 characters';
                                  }
                                  if (val.trim() == _oldPasswordController.text.trim()) {
                                    return isArabic ? 'لا يمكن استخدام نفس كلمة المرور الحالية' : 'Cannot match current password';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              // Confirm Password Field
                              Text(
                                isArabic ? 'تأكيد كلمة المرور الجديدة' : 'Confirm New Password',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: _obscureConfirm,
                                enabled: !_isLoading,
                                decoration: InputDecoration(
                                  hintText: isArabic ? 'أعد إدخال كلمة المرور الجديدة' : 'Re-enter new password',
                                  prefixIcon: const Icon(Icons.lock_rounded),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                                  ),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return isArabic ? 'يرجى تأكيد كلمة المرور الجديدة' : 'Confirm password is required';
                                  }
                                  if (val.trim() != _newPasswordController.text.trim()) {
                                    return isArabic ? 'كلمتا المرور غير متطابقتين' : 'Passwords do not match';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 32),

                              // Submit Button
                              ElevatedButton(
                                onPressed: _isLoading ? null : _handleChangePassword,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  minimumSize: const Size.fromHeight(56),
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : Text(
                                        isArabic ? 'تحديث كلمة المرور والدخول' : 'Update Password & Enter',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
