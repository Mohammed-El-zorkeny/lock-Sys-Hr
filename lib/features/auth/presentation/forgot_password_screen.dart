import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_dimensions.dart';
import '../../../routing/app_routes.dart';

enum ForgotPasswordStep { phoneOrNationalId, otp, resetPassword }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  ForgotPasswordStep _currentStep = ForgotPasswordStep.phoneOrNationalId;

  // Controllers
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // OTP controllers and focus nodes
  final List<TextEditingController> _otpControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(4, (_) => FocusNode());

  // Password visibility
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  // Resend Timer
  Timer? _resendTimer;
  int _secondsRemaining = 60;
  bool _canResend = false;

  // Form keys for validation
  final _formKey1 = GlobalKey<FormState>();
  final _formKey3 = GlobalKey<FormState>();

  @override
  void dispose() {
    _identifierController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _otpFocusNodes) {
      node.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _secondsRemaining = 60;
      _canResend = false;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        setState(() {
          _canResend = true;
          _resendTimer?.cancel();
        });
      }
    });
  }

  void _handleResendCode() {
    if (!_canResend) return;
    _startResendTimer();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إعادة إرسال رمز التحقق بنجاح'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _moveToStep2() {
    if (_formKey1.currentState?.validate() ?? false) {
      setState(() {
        _currentStep = ForgotPasswordStep.otp;
      });
      _startResendTimer();
      // Auto focus on the first OTP cell
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _otpFocusNodes[0].requestFocus();
      });
    }
  }

  void _moveToStep3() {
    // Validate OTP
    String otp = _otpControllers.map((c) => c.text).join();
    if (otp.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال رمز التحقق المكون من 4 أرقام كاملاً'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() {
      _currentStep = ForgotPasswordStep.resetPassword;
    });
  }

  void _submitNewPassword() {
    if (_formKey3.currentState?.validate() ?? false) {
      // Show success dialog and navigate back
      _showSuccessDialog();
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.spaceLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppColors.success,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spaceLg),
                  Text(
                    'تم تغيير كلمة السر بنجاح!',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppDimensions.spaceSm),
                  Text(
                    'يمكنك الآن تسجيل الدخول باستخدام كلمة السر الجديدة.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppDimensions.spaceLg),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Dismiss Dialog
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        AppRoutes.login,
                        (route) => false,
                      );
                    },
                    child: const Text('الانتقال لتسجيل الدخول'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (_currentStep == ForgotPasswordStep.resetPassword) {
                setState(() => _currentStep = ForgotPasswordStep.otp);
              } else if (_currentStep == ForgotPasswordStep.otp) {
                setState(
                  () => _currentStep = ForgotPasswordStep.phoneOrNationalId,
                );
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          title: const Text('إعادة تعيين كلمة السر'),
        ),
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
                        const SizedBox(height: AppDimensions.spaceMd),
                        _BrandMark(step: _currentStep),
                        const SizedBox(height: AppDimensions.spaceLg),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.05, 0.0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _buildStepContent(),
                        ),
                        const Spacer(),
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

  Widget _buildStepContent() {
    switch (_currentStep) {
      case ForgotPasswordStep.phoneOrNationalId:
        return _buildStep1PhoneOrId();
      case ForgotPasswordStep.otp:
        return _buildStep2OTP();
      case ForgotPasswordStep.resetPassword:
        return _buildStep3Reset();
    }
  }

  Widget _buildStep1PhoneOrId() {
    return Form(
      key: _formKey1,
      child: Column(
        key: const ValueKey('step1'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'هل نسيت كلمة السر؟',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimensions.spaceSm),
          Text(
            'أدخل رقم الهاتف المحمول أو الرقم القومي المرتبط بحسابك وسنقوم بإرسال رمز تحقق لتأكيد هويتك.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),
          _SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _identifierController,
                  keyboardType: TextInputType.text,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'يرجى إدخال رقم الهاتف أو الرقم القومي';
                    }
                    if (value.trim().length < 8) {
                      return 'الرقم المدخل غير صالح';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    hintText: 'رقم الهاتف أو الرقم القومي',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),
          ElevatedButton.icon(
            onPressed: _moveToStep2,
            icon: const Icon(Icons.send_rounded, size: AppDimensions.iconMd),
            label: const Text('إرسال رمز التحقق'),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2OTP() {
    return Column(
      key: const ValueKey('step2'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'أدخل رمز التحقق (OTP)',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDimensions.spaceSm),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            children: [
              const TextSpan(text: 'تم إرسال رمز التحقق إلى الرقم '),
              TextSpan(
                text: _identifierController.text,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.spaceLg),
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(4, (index) {
                  return SizedBox(
                    width: 56,
                    height: 56,
                    child: TextFormField(
                      controller: _otpControllers[index],
                      focusNode: _otpFocusNodes[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        counterText: '',
                        contentPadding: EdgeInsets.zero,
                        fillColor: AppColors.field,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusMd,
                          ),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusMd,
                          ),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          if (index < 3) {
                            _otpFocusNodes[index + 1].requestFocus();
                          } else {
                            _otpFocusNodes[index].unfocus();
                            // Optional: auto verify when all digits are entered
                            _moveToStep3();
                          }
                        } else {
                          if (index > 0) {
                            _otpFocusNodes[index - 1].requestFocus();
                          }
                        }
                      },
                    ),
                  );
                }),
              ),
              const SizedBox(height: AppDimensions.spaceLg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _canResend ? 'لم يصلك الرمز؟ ' : 'إعادة إرسال الرمز خلال ',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (!_canResend)
                    Text(
                      '$_secondsRemaining ثانية',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (_canResend)
                    TextButton(
                      onPressed: _handleResendCode,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('إعادة الإرسال'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.spaceLg),
        ElevatedButton(onPressed: _moveToStep3, child: const Text('تأكيد')),
      ],
    );
  }

  Widget _buildStep3Reset() {
    return Form(
      key: _formKey3,
      child: Column(
        key: const ValueKey('step3'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'إنشاء كلمة سر جديدة',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimensions.spaceSm),
          Text(
            'يرجى إدخال كلمة السر الجديدة وتأكيدها. تأكد من اختيار كلمة سر قوية وسهلة التذكر بالنسبة لك.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),
          _SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscureNewPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'يرجى إدخال كلمة السر الجديدة';
                    }
                    if (value.length < 6) {
                      return 'يجب أن تكون كلمة السر من 6 أحرف أو أرقام على الأقل';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    hintText: 'كلمة السر الجديدة',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNewPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureNewPassword = !_obscureNewPassword;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceMd),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'يرجى تأكيد كلمة السر الجديدة';
                    }
                    if (value != _newPasswordController.text) {
                      return 'كلمتا السر غير متطابقتين';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    hintText: 'تأكيد كلمة السر الجديدة',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),
          ElevatedButton(
            onPressed: _submitNewPassword,
            child: const Text('حفظ كلمة السر الجديدة'),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.step});

  final ForgotPasswordStep step;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (step) {
      case ForgotPasswordStep.phoneOrNationalId:
        icon = Icons.lock_reset_rounded;
        color = AppColors.primary;
        break;
      case ForgotPasswordStep.otp:
        icon = Icons.mark_email_unread_rounded;
        color = AppColors.secondary;
        break;
      case ForgotPasswordStep.resetPassword:
        icon = Icons.security_rounded;
        color = AppColors.success;
        break;
    }

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        ),
        child: Icon(icon, color: color, size: 32),
      ),
    );
  }
}

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
