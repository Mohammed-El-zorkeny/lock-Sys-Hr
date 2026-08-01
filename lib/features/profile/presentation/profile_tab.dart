import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_settings_controller.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimensions.dart';
import '../../../core/utils/attendance_logger.dart';

/// Profile tab screen displaying user details and logout action.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  String _name = '';
  String _code = '';
  String _dept = '';
  String _job = '';
  String _site = '';
  String _hireDate = '';
  String _email = '';
  String _phone = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(AttendanceLogger.logScreenActivity('PROFILE'));
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final name = await AuthStorage.getEmployeeNameAr();
    final code = await AuthStorage.getEmployeeCode();
    final dept = await AuthStorage.getDepartmentNameAr();
    final job = await AuthStorage.getJobTitleAr();
    final site = await AuthStorage.getSiteNameAr();
    final hireDate = await AuthStorage.getHireDate();
    final email = await AuthStorage.getEmail();
    final phone = await AuthStorage.getPhone();

    if (mounted) {
      setState(() {
        _name = name;
        _code = code;
        _dept = dept;
        _job = job;
        _site = site;
        _hireDate = hireDate;
        _email = email;
        _phone = phone;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    await AuthStorage.clearSession();
    if (mounted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('الملف الشخصي'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spaceLg,
            vertical: AppDimensions.spaceLg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProfileHeader(name: _name, code: _code),
              const SizedBox(height: AppDimensions.spaceLg),
              _ProfileDetailsCard(
                dept: _dept,
                job: _job,
                site: _site,
                hireDate: _hireDate,
                email: _email,
                phone: _phone,
              ),
              const SizedBox(height: AppDimensions.spaceLg),
              AnimatedBuilder(
                animation: AppSettingsController.instance,
                builder: (context, _) {
                  return _AppSettingsCard(settings: AppSettingsController.instance);
                },
              ),
              const SizedBox(height: AppDimensions.spaceLg),
              OutlinedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(
                  Icons.logout_rounded,
                  size: AppDimensions.iconMd,
                ),
                label: const Text('تسجيل الخروج'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  backgroundColor: AppColors.error.withValues(alpha: 0.04),
                ),
              ),
              const SizedBox(height: AppDimensions.spaceLg),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.name, required this.code});

  final String name;
  final String code;

  @override
  Widget build(BuildContext context) {
    final String initial = name.isNotEmpty
        ? name.trim().split(' ').first[0]
        : 'U';

    return Center(
      child: Column(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.secondary, AppColors.accent],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.15),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),
          Text(
            name.isNotEmpty ? name : 'الموظف الكريم',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          if (code.isNotEmpty) ...[
            const SizedBox(height: AppDimensions.spaceXs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.field,
                borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                'كود الموظف: $code',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileDetailsCard extends StatelessWidget {
  const _ProfileDetailsCard({
    required this.dept,
    required this.job,
    required this.site,
    required this.hireDate,
    required this.email,
    required this.phone,
  });

  final String dept;
  final String job;
  final String site;
  final String hireDate;
  final String email;
  final String phone;

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
            color: AppColors.primary.withValues(alpha: 0.02),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _ProfileRowItem(
            icon: Icons.business_rounded,
            label: 'القسم',
            value: dept,
          ),
          const Divider(
            color: AppColors.divider,
            height: AppDimensions.spaceLg,
          ),
          _ProfileRowItem(
            icon: Icons.work_outline_rounded,
            label: 'المسمى الوظيفي',
            value: job,
          ),
          const Divider(
            color: AppColors.divider,
            height: AppDimensions.spaceLg,
          ),
          _ProfileRowItem(
            icon: Icons.location_on_outlined,
            label: 'موقع العمل',
            value: site,
          ),
          const Divider(
            color: AppColors.divider,
            height: AppDimensions.spaceLg,
          ),
          _ProfileRowItem(
            icon: Icons.calendar_month_outlined,
            label: 'تاريخ التعيين',
            value: hireDate,
          ),
          if (email.isNotEmpty) ...[
            const Divider(
              color: AppColors.divider,
              height: AppDimensions.spaceLg,
            ),
            _ProfileRowItem(
              icon: Icons.email_outlined,
              label: 'البريد الإلكتروني',
              value: email,
            ),
          ],
          if (phone.isNotEmpty) ...[
            const Divider(
              color: AppColors.divider,
              height: AppDimensions.spaceLg,
            ),
            _ProfileRowItem(
              icon: Icons.phone_outlined,
              label: 'الهاتف',
              value: phone,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileRowItem extends StatelessWidget {
  const _ProfileRowItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.textSecondary, size: AppDimensions.iconMd),
        const SizedBox(width: AppDimensions.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value.isNotEmpty ? value : 'غير محدد',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppSettingsCard extends StatelessWidget {
  const _AppSettingsCard({required this.settings});

  final AppSettingsController settings;

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
            color: AppColors.primary.withValues(alpha: 0.02),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.settings_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'إعدادات التطبيق',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.divider, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.language_rounded, color: AppColors.textSecondary, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'لغة التطبيق',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => settings.toggleLanguage(),
                child: Text(
                  settings.isArabic ? 'English' : 'العربية',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.divider, height: 16),
          const Text(
            'حجم خط التطبيق',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildFontScaleChip(context, 'صغير', 0.85),
              _buildFontScaleChip(context, 'طبيعي', 1.0),
              _buildFontScaleChip(context, 'كبير', 1.15),
              _buildFontScaleChip(context, 'كبير جداً', 1.3),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFontScaleChip(BuildContext context, String label, double scale) {
    final isSelected = (settings.fontSizeScale - scale).abs() < 0.01;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : AppColors.textPrimary,
        ),
      ),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.field,
      onSelected: (selected) {
        if (selected) {
          settings.setFontSizeScale(scale);
        }
      },
    );
  }
}
