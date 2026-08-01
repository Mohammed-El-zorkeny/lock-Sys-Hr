import 'dart:async';
import 'package:flutter/material.dart';

import '../../../core/storage/auth_storage.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimensions.dart';
import '../../../core/utils/attendance_logger.dart';
import '../../dailies/presentation/dailies_screen.dart';
import '../../attendance/presentation/my_check_in_screen.dart';

/// Home tab — HR dashboard (UI). Crimson Corporate theme.
/// Displays greeting and only two main actions: "تحضيري" and "اليوميات".
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  String _employeeName = '';
  String _jobTitle = '';
  bool _isLoading = true;
  bool _allowAttendance = true;
  bool _allowDailies = true;

  @override
  void initState() {
    super.initState();
    unawaited(AttendanceLogger.logScreenActivity('HOME'));
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final name = await AuthStorage.getEmployeeNameAr();
    final job = await AuthStorage.getJobTitleAr();
    final allowAtt = await AuthStorage.isAttendanceAllowed();
    final allowDai = await AuthStorage.isDailiesAllowed();
    if (mounted) {
      setState(() {
        _employeeName = name;
        _jobTitle = job;
        _allowAttendance = allowAtt;
        _allowDailies = allowDai;
        _isLoading = false;
      });
    }
  }

  String _limitWords(String text, int maxWords) {
    if (text.isEmpty) return text;
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.length <= maxWords) return text;
    return words.take(maxWords).join(' ');
  }

  Widget _buildMainServicesWidgets() {
    final List<Widget> cards = [];

    if (_allowAttendance) {
      cards.add(
        _InteractiveDashboardCard(
          title: 'تسجيل التحضير',
          description: 'تسجيل الحضور والانصراف بالبصمة والموقع',
          icon: Icons.fingerprint_rounded,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.accent],
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyCheckInScreen()),
            );
          },
        ),
      );
    }

    if (_allowDailies) {
      cards.add(
        _InteractiveDashboardCard(
          title: 'اليوميات والأنشطة',
          description: 'إضافة ومتابعة تقاريرك وأنشطتك اليومية',
          icon: Icons.calendar_today_rounded,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.secondary, AppColors.primary],
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DailiesScreen()),
            );
          },
        ),
      );
    }

    if (cards.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Column(
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 36),
            SizedBox(height: 12),
            Text(
              'لا توجد خدمات نشطة لحسابك حالياً. يرجى مراجعة المسؤول.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (cards.length == 1) {
      return cards.first;
    }

    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: AppDimensions.spaceMd),
        Expanded(child: cards[1]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final name = _employeeName.isNotEmpty ? _limitWords(_employeeName, 3) : 'مايكل مجدي جرجس';
    final role = _jobTitle.isNotEmpty ? _limitWords(_jobTitle, 4) : 'مدير عام تكنولوجيا المعلومات';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppDimensions.spaceLg),
          children: [
            // Crimson Gradient Header with custom wave pattern
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                child: Stack(
                  children: [
                    // Premium Custom wave painter
                    Positioned.fill(
                      child: CustomPaint(
                        painter: HeaderWavePainter(),
                      ),
                    ),
                    // Content column
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TopBar(name: name, role: role),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spaceLg),
            
            // Dashboard section title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceMd + 4),
              child: const Text(
                'الخدمات الرئيسية',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spaceSm),

            // Dynamic Actions: Attendance (تحضيري) and Dailies (اليوميات)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceMd),
              child: _buildMainServicesWidgets(),
            ),

          ],
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'م';
  if (parts.length == 1) return parts.first.characters.first;
  return '${parts[0].characters.first} ${parts[1].characters.first}';
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.name, required this.role});

  final String name;
  final String role;

  void _showComingSoonSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'هذه الميزة ستتوفر قريباً!',
          style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.spaceMd,
        AppDimensions.spaceMd,
        AppDimensions.spaceMd,
        0,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              _initials(name),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: AppDimensions.spaceSm + 3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'مرحبا بك 👋',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontSize: 17,
                  ),
                ),
                Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _SquareIconButton(
            icon: Icons.notifications_none_rounded,
            badge: true,
            onTap: () => _showComingSoonSnackBar(context),
          ),
          const SizedBox(width: AppDimensions.spaceSm),
          _SquareIconButton(
            icon: Icons.grid_view_rounded,
            onTap: () => _showComingSoonSnackBar(context),
          ),
        ],
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({required this.icon, this.badge = false, this.onTap});

  final IconData icon;
  final bool badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: AppDimensions.iconMd, color: Colors.white),
            if (badge)
              Positioned(
                top: 9,
                right: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InteractiveDashboardCard extends StatefulWidget {
  final String title;
  final String description;
  final IconData icon;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _InteractiveDashboardCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  State<_InteractiveDashboardCard> createState() => _InteractiveDashboardCardState();
}

class _InteractiveDashboardCardState extends State<_InteractiveDashboardCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          height: 170,
          padding: const EdgeInsets.all(AppDimensions.spaceMd + 2),
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: widget.gradient.colors.first.withValues(alpha: 0.16),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  widget.icon,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const Spacer(),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.8),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



/// A custom painter to draw premium, elegant translucent curves/waves
/// behind the red gradient header.
class HeaderWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Draw top-right corner subtle radial circle
    paint.color = Colors.white.withValues(alpha: 0.04);
    canvas.drawCircle(
      Offset(size.width * 0.9, size.height * 0.15),
      size.width * 0.45,
      paint,
    );

    // Draw first bezier wave at the bottom-ish
    final path1 = Path();
    path1.moveTo(0, size.height * 0.65);
    path1.cubicTo(
      size.width * 0.3,
      size.height * 0.45,
      size.width * 0.6,
      size.height * 0.9,
      size.width,
      size.height * 0.55,
    );
    path1.lineTo(size.width, size.height);
    path1.lineTo(0, size.height);
    path1.close();

    paint.color = Colors.white.withValues(alpha: 0.035);
    canvas.drawPath(path1, paint);

    // Draw second overlapping bezier wave
    final path2 = Path();
    path2.moveTo(0, size.height * 0.45);
    path2.cubicTo(
      size.width * 0.25,
      size.height * 0.65,
      size.width * 0.7,
      size.height * 0.35,
      size.width,
      size.height * 0.75,
    );
    path2.lineTo(size.width, size.height);
    path2.lineTo(0, size.height);
    path2.close();

    paint.color = Colors.white.withValues(alpha: 0.03);
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
