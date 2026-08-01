import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../app/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimensions.dart';
import '../../../core/utils/attendance_logger.dart';
import '../../home/presentation/home_tab.dart' show HeaderWavePainter;

/// Today's logs / Dailies Screen.
/// Displays a horizontal week calendar filter, tabs for presence/absence/leave/holidays, and a list of employee logs.
class DailiesScreen extends StatefulWidget {
  const DailiesScreen({super.key});

  @override
  State<DailiesScreen> createState() => _DailiesScreenState();
}

class _DailiesScreenState extends State<DailiesScreen> {
  final DateTime _today = DateTime.now();
  late DateTime _selectedDate;
  late List<DateTime> _dates;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  late List<_DailyLog> _allLogs;
  String _selectedStatusTab = 'present'; // Default tab: الحضور
  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _leaveTypes = [];
  List<Map<String, dynamic>> _missionTypes = [
    {'id': 2, 'nameAr': 'داخلية', 'nameEn': 'Inside', 'classification': 'IN'},
    {'id': 3, 'nameAr': 'خارجية', 'nameEn': 'Outside', 'classification': 'OUT'},
  ];
  final Set<String> _collapsedDepartments = {};

  @override
  void initState() {
    super.initState();
    unawaited(AttendanceLogger.logScreenActivity('DAILIES'));
    _selectedDate = DateTime(_today.year, _today.month, _today.day);
    // Generate dates: 5 preceding days, today, and 10 following days (total 16 days)
    _dates = List.generate(16, (index) => _selectedDate.add(Duration(days: index - 5)));
    
    _allLogs = [];
    _loadAttendanceForDate(_selectedDate);
    _loadLeaveTypes();
    _loadMissionTypes();

    // Auto-scroll to center on today's date
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToToday();
    });
  }

  Future<void> _loadAttendanceForDate(DateTime date) async {
    if (!mounted) return;
    
    final todayMidnight = DateTime(_today.year, _today.month, _today.day);
    final bool isFuture = date.isAfter(todayMidnight);

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _collapsedDepartments.clear();
      if (isFuture) {
        _selectedStatusTab = 'holiday';
      }
    });

    try {
      final formattedDate =
          '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
      final url = '${AppConfig.baseUrl}/MyEmployees/Present?date_filter=$formattedDate';

      final response = await ApiClient.get(url);
      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final List<dynamic> attendanceList = responseData['attendance'] ?? [];
        if (mounted) {
          setState(() {
            _allLogs = attendanceList
                .map((json) => _DailyLog.fromJson(json, date))
                .toList();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = responseData['messageAr'] ?? 'فشل جلب بيانات الحضور';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading attendance: $e');
      if (mounted) {
        setState(() {
          _errorMessage =
              'حدث خطأ في الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.';
          _isLoading = false;
        });
      }
    }
  }

  void _scrollToToday() {
    final todayIndex = _dates.indexWhere((date) =>
        date.year == _today.year &&
        date.month == _today.month &&
        date.day == _today.day);
    if (todayIndex != -1) {
      const itemWidth = 60.0; // item width 52 + horizontal gap (4 * 2) = 60
      final screenWidth = MediaQuery.of(context).size.width;
      final offset = (todayIndex * itemWidth) - (screenWidth / 2) + (itemWidth / 2);
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          offset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<_DailyLog> _getFilteredLogs() {
    var dateLogs = List<_DailyLog>.from(_allLogs);

    // 2. Filter by status tab
    switch (_selectedStatusTab) {
      case 'present':
        dateLogs = dateLogs.where((log) =>
            (log.attendanceStatus.contains('COMPLETE') ||
             log.attendanceStatus.contains('NO_CHECKOUT') ||
             log.attendanceStatus.contains('PRESENT') ||
             log.checkInTime != null) &&
            !log.attendanceStatus.contains('NOT_PRESENT')).toList();
        break;
      case 'absent':
        dateLogs = dateLogs.where((log) =>
            log.attendanceStatus.contains('ABSENT') ||
            log.attendanceStatus.contains('NOT_PRESENT')).toList();
        break;
      case 'leave':
        dateLogs = dateLogs.where((log) =>
            log.attendanceStatus.contains('LEAVE') ||
            log.attendanceStatus.contains('VACATION')).toList();
        break;
      case 'holiday':
        dateLogs = dateLogs.where((log) =>
            log.attendanceStatus.contains('HOLIDAY') ||
            log.attendanceStatus.contains('WEEKEND') ||
            log.attendanceStatus.contains('PUBLIC_HOLIDAY') ||
            log.attendanceStatus.contains('WEEKLY_OFF')).toList();
        break;
    }

    // 3. Filter by search query (Name, Dept, Code)
    if (_searchQuery.isEmpty) return dateLogs;

    return dateLogs.where((log) {
      final nameMatch =
          log.nameAr.contains(_searchQuery) || log.nameEn.contains(_searchQuery);
      final deptMatch = log.departmentName.contains(_searchQuery);
      final codeMatch = log.employeeCode.contains(_searchQuery);
      return nameMatch || deptMatch || codeMatch;
    }).toList();
  }

  String _getArabicDayNameShort(int weekday) {
    switch (weekday) {
      case DateTime.sunday:
        return 'أحد';
      case DateTime.monday:
        return 'إثنين';
      case DateTime.tuesday:
        return 'ثلاثاء';
      case DateTime.wednesday:
        return 'أربعاء';
      case DateTime.thursday:
        return 'خميس';
      case DateTime.friday:
        return 'جمعة';
      case DateTime.saturday:
        return 'سبت';
      default:
        return '';
    }
  }

  String _getArabicMonthName(int month) {
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];
    if (month >= 1 && month <= 12) {
      return months[month - 1];
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _getFilteredLogs();
    final todayMidnight = DateTime(_today.year, _today.month, _today.day);
    final bool isFutureDate = _selectedDate.isAfter(todayMidnight);

    // Group logs by department
    final Map<String, List<_DailyLog>> logsByDept = {};
    for (var log in filteredLogs) {
      final deptName = log.departmentName.trim().isEmpty ? 'أقسام أخرى' : log.departmentName.trim();
      logsByDept.putIfAbsent(deptName, () => []).add(log);
    }
    // Sort departments alphabetically
    final depts = logsByDept.keys.toList()..sort();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('اليوميات'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Week Calendar selector
              Padding(
                padding: const EdgeInsets.all(AppDimensions.spaceMd),
                child: Container(
                  height: 85,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      children: [
                        // Reuse the custom waves painter
                        Positioned.fill(
                          child: CustomPaint(
                            painter: HeaderWavePainter(),
                          ),
                        ),
                        Column(
                          children: [
                            const SizedBox(height: 6),
                            // Current selected month label in small font size
                            Text(
                              '${_getArabicMonthName(_selectedDate.month)} ${_selectedDate.year}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                controller: _scrollController,
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                itemCount: _dates.length,
                                itemBuilder: (context, index) {
                                  final date = _dates[index];
                                  final isSelected =
                                      date.year == _selectedDate.year &&
                                          date.month == _selectedDate.month &&
                                          date.day == _selectedDate.day;
                                  final isToday =
                                      date.year == _today.year &&
                                          date.month == _today.month &&
                                          date.day == _today.day;

                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedDate = date;
                                      });
                                      _loadAttendanceForDate(date);
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      width: 52,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white
                                            : isToday
                                                ? Colors.white.withValues(alpha: 0.15)
                                                : Colors.transparent,
                                        borderRadius: BorderRadius.circular(14),
                                        border: isToday && !isSelected
                                            ? Border.all(
                                                color: Colors.white.withValues(
                                                  alpha: 0.80,
                                                ),
                                                width: 1.5,
                                              )
                                            : null,
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _getArabicDayNameShort(date.weekday),
                                            style: TextStyle(
                                              color: isSelected
                                                  ? AppColors.primary
                                                  : Colors.white.withValues(
                                                    alpha: 0.70,
                                                  ),
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            date.day.toString(),
                                            style: TextStyle(
                                              color: isSelected
                                                  ? AppColors.primary
                                                  : Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          if (isToday) ...[
                                            const SizedBox(height: 1),
                                            Container(
                                              width: 4,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? AppColors.primary
                                                    : Colors.white,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Selected Date label
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spaceMd,
                ),
                child: Text(
                  'يوميات تاريخ: ${_selectedDate.day} ${_getArabicMonthName(_selectedDate.month)} ${_selectedDate.year}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Four tabs next to each other
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceMd),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      if (!isFutureDate) ...[
                        _StatusTabItem(
                          label: 'الحضور',
                          icon: Icons.check_circle_outline_rounded,
                          isSelected: _selectedStatusTab == 'present',
                          activeColor: const Color(0xFF10B981),
                          activeGradient: const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF059669)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          onTap: () {
                            setState(() {
                              _selectedStatusTab = 'present';
                              _collapsedDepartments.clear();
                            });
                          },
                        ),
                        _StatusTabItem(
                          label: 'الغياب',
                          icon: Icons.cancel_outlined,
                          isSelected: _selectedStatusTab == 'absent',
                          activeColor: const Color(0xFFEF4444),
                          activeGradient: const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          onTap: () {
                            setState(() {
                              _selectedStatusTab = 'absent';
                              _collapsedDepartments.clear();
                            });
                          },
                        ),
                        _StatusTabItem(
                          label: 'الإجازات',
                          icon: Icons.beach_access_rounded,
                          isSelected: _selectedStatusTab == 'leave',
                          activeColor: const Color(0xFF3B82F6),
                          activeGradient: const LinearGradient(
                            colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          onTap: () {
                            setState(() {
                              _selectedStatusTab = 'leave';
                              _collapsedDepartments.clear();
                            });
                          },
                        ),
                      ],
                      _StatusTabItem(
                        label: 'الراحات والعطلات',
                        icon: Icons.weekend_rounded,
                        isSelected: _selectedStatusTab == 'holiday',
                        activeColor: const Color(0xFF8B5CF6),
                        activeGradient: const LinearGradient(
                          colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        onTap: () {
                          setState(() {
                            _selectedStatusTab = 'holiday';
                            _collapsedDepartments.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // Search box (Name, Dept, Code)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.spaceMd,
                  10,
                  AppDimensions.spaceMd,
                  12,
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم، القسم، أو الكود...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                        : null,
                    fillColor: AppColors.surface,
                  ),
                ),
              ),

              // Daily Logs list
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _loadAttendanceForDate(_selectedDate),
                  color: AppColors.primary,
                  child: _isLoading
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: AppColors.primary),
                              SizedBox(height: 16),
                              Text(
                                'جاري تحميل بيانات الحضور...',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _errorMessage != null
                          ? SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(AppDimensions.spaceLg),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 80),
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: AppColors.error,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () => _loadAttendanceForDate(_selectedDate),
                                    icon: const Icon(Icons.refresh_rounded, size: 18),
                                    label: const Text(
                                      'إعادة المحاولة',
                                      style: TextStyle(fontFamily: 'Cairo'),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : filteredLogs.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  children: const [
                                    SizedBox(height: 100),
                                    _EmptyState(),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        AppDimensions.spaceMd,
                                        4,
                                        AppDimensions.spaceMd,
                                        8,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: AppColors.primary.withValues(alpha: 0.12),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.business_rounded,
                                                  color: AppColors.primary,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'عدد الأقسام: ${depts.length}',
                                                  style: const TextStyle(
                                                    fontFamily: 'Cairo',
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.people_alt_rounded,
                                                  color: AppColors.primary,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'إجمالي الموظفين: ${filteredLogs.length}',
                                                  style: const TextStyle(
                                                    fontFamily: 'Cairo',
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: ListView.builder(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppDimensions.spaceMd,
                                        ),
                                        itemCount: depts.length,
                                        itemBuilder: (context, index) {
                                          final deptName = depts[index];
                                          final deptLogs = logsByDept[deptName] ?? [];
                                          final isCollapsed = _collapsedDepartments.contains(deptName);

                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 12),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                InkWell(
                                                  onTap: () {
                                                    setState(() {
                                                      if (isCollapsed) {
                                                        _collapsedDepartments.remove(deptName);
                                                      } else {
                                                        _collapsedDepartments.add(deptName);
                                                      }
                                                    });
                                                  },
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.surface,
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(
                                                        color: AppColors.border,
                                                        width: 0.8,
                                                      ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black.withValues(alpha: 0.02),
                                                          blurRadius: 4,
                                                          offset: const Offset(0, 2),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.all(6),
                                                          decoration: BoxDecoration(
                                                            color: AppColors.primary.withValues(alpha: 0.08),
                                                            borderRadius: BorderRadius.circular(8),
                                                          ),
                                                          child: const Icon(
                                                            Icons.corporate_fare_rounded,
                                                            color: AppColors.primary,
                                                            size: 18,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Expanded(
                                                          child: Text(
                                                            deptName,
                                                            style: const TextStyle(
                                                              fontFamily: 'Cairo',
                                                              fontSize: 13,
                                                              fontWeight: FontWeight.w800,
                                                              color: AppColors.textPrimary,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                                          decoration: BoxDecoration(
                                                            color: AppColors.primary.withValues(alpha: 0.1),
                                                            borderRadius: BorderRadius.circular(20),
                                                          ),
                                                          child: Text(
                                                            '${deptLogs.length} ${deptLogs.length >= 3 && deptLogs.length <= 10 ? 'موظفين' : 'موظف'}',
                                                            style: const TextStyle(
                                                              fontFamily: 'Cairo',
                                                              fontSize: 10.5,
                                                              fontWeight: FontWeight.bold,
                                                              color: AppColors.primary,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 10),
                                                        Icon(
                                                          isCollapsed
                                                              ? Icons.keyboard_arrow_left_rounded
                                                              : Icons.keyboard_arrow_down_rounded,
                                                          color: AppColors.textSecondary,
                                                          size: 20,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                if (!isCollapsed) ...[
                                                  const SizedBox(height: 8),
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                                    child: Column(
                                                      children: deptLogs.map((log) {
                                                        return _DailyLogTile(
                                                          log: log,
                                                          onTap: () => _showActionBottomSheet(context, log),
                                                        );
                                                      }).toList(),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        },
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
    );
  }

  void _showCancelOvertimeWarningDialog(BuildContext sheetContext, _DailyLog log) {
    if (log.overtime == null) return;
    
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'إلغاء الساعات الإضافية',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'الموظف: ${log.nameAr}',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'سيتم إلغاء طلب الساعات الإضافية (إضافي أجر) الحالي للموظف. هل أنت متأكد من الاستمرار؟',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text(
                    'تراجع',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() {
                            isSubmitting = true;
                          });
                          
                          final success = await _updateOvertimeRequest(
                            context,
                            id: log.overtime!.id,
                            fromTime: log.overtime!.fromTime,
                            toTime: log.overtime!.toTime,
                            notes: 'إلغاء إضافي أجر',
                            status: 0,
                          );
                          
                          if (success && context.mounted) {
                            Navigator.pop(dialogContext); // Close warning dialog
                            
                            // Reload attendance logs from server to reflect fresh status
                            await _loadAttendanceForDate(log.date);
                          } else {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'تأكيد الإلغاء',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditOvertimeDialog(BuildContext sheetContext, _DailyLog log) {
    if (log.overtime == null) return;
    
    // Parse current fromTime and toTime
    TimeOfDay fromTime = const TimeOfDay(hour: 17, minute: 0);
    TimeOfDay toTime = const TimeOfDay(hour: 20, minute: 0);
    
    try {
      final fromParts = log.overtime!.fromTime.split(':');
      if (fromParts.length >= 2) {
        fromTime = TimeOfDay(hour: int.parse(fromParts[0]), minute: int.parse(fromParts[1]));
      }
      final toParts = log.overtime!.toTime.split(':');
      if (toParts.length >= 2) {
        toTime = TimeOfDay(hour: int.parse(toParts[0]), minute: int.parse(toParts[1]));
      }
    } catch (e) {
      debugPrint('Error parsing initial overtime times: $e');
    }

    final notesController = TextEditingController(text: 'تعديل ساعات إضافية');
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final fromText = '${fromTime.hour.toString().padLeft(2, '0')}:${fromTime.minute.toString().padLeft(2, '0')}';
            final toText = '${toTime.hour.toString().padLeft(2, '0')}:${toTime.minute.toString().padLeft(2, '0')}';

            return AlertDialog(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.edit_calendar_rounded,
                      color: Colors.orange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'تعديل الساعات الإضافية',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'الموظف: ${log.nameAr}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: isSubmitting
                                  ? null
                                  : () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: fromTime,
                                      );
                                      if (picked != null) {
                                        setDialogState(() {
                                          fromTime = picked;
                                        });
                                      }
                                    },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'من وقت (البدء)',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                child: Text(
                                  fromText,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: isSubmitting
                                  ? null
                                  : () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: toTime,
                                      );
                                      if (picked != null) {
                                        setDialogState(() {
                                          toTime = picked;
                                        });
                                      }
                                    },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'إلى وقت (الانتهاء)',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                child: Text(
                                  toText,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'الملاحظات',
                          hintText: 'مثال: تعديل مواعيد العمل الإضافي المسائي',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() {
                              isSubmitting = true;
                            });

                            final success = await _updateOvertimeRequest(
                              context,
                              id: log.overtime!.id,
                              fromTime: fromText,
                              toTime: toText,
                              notes: notesController.text.trim(),
                              status: 1,
                            );

                            if (success && context.mounted) {
                              Navigator.pop(dialogContext); // Close dialog
                              
                              // Reload list from server
                              await _loadAttendanceForDate(log.date);
                            } else {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'تعديل',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _updateOvertimeRequest(
    BuildContext context, {
    required int id,
    required String fromTime,
    required String toTime,
    required String notes,
    required int status,
  }) async {
    try {
      final url = '${AppConfig.baseUrl}/MyEmployees/UpdateOvertimeRequests?id=$id';
      final requestBody = {
        'fromTime': fromTime,
        'toTime': toTime,
        'notes': notes.isNotEmpty ? notes : (status == 1 ? 'تعديل إضافي' : 'إلغاء إضافي'),
        'status': status,
      };

      final response = await ApiClient.post(url, body: requestBody);
      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                responseData['messageAr'] ?? (status == 1 ? 'تم تعديل الطلب بنجاح' : 'تم إلغاء الطلب بنجاح'),
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
        return true;
      } else {
        final errorMsg = responseData['messageAr'] ?? 'فشل تعديل ساعات الإضافي';
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorMsg,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('Error updating overtime request: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'حدث خطأ أثناء تعديل ساعات الإضافي',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  void _showCancelCtoDialog(BuildContext sheetContext, _DailyLog log) {
    if (log.cto == null) return;
    
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'إلغاء بدل يعوض',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'الموظف: ${log.nameAr}',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'سيتم إلغاء ساعات التعويض (بدل يعوض) الحالية للموظف. هل أنت متأكد من الاستمرار؟',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text(
                    'تراجع',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() {
                            isSubmitting = true;
                          });
                          
                          final success = await _cancelCto(context, log.cto!.id);
                          
                          if (success && context.mounted) {
                            Navigator.pop(dialogContext); // Close warning dialog
                            
                            // Reload attendance logs from server to reflect fresh status
                            await _loadAttendanceForDate(log.date);
                          } else {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'تأكيد الإلغاء',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _cancelCto(BuildContext context, int ctoId) async {
    try {
      final url = '${AppConfig.baseUrl}/MyEmployees/NotActiveCto?id=$ctoId';
      final response = await ApiClient.post(url, body: {});
      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                responseData['messageAr'] ?? 'تم إلغاء ساعات التعويض بنجاح',
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
        return true;
      } else {
        final errorMsg = responseData['messageAr'] ?? 'فشل إلغاء ساعات التعويض';
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorMsg,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('Error cancelling CTO: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'حدث خطأ أثناء إلغاء ساعات التعويض',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  void _showActionBottomSheet(BuildContext context, _DailyLog log) {
    final isAbsent = log.attendanceStatus == 'ABSENT' || log.attendanceStatus == 'NOT_PRESENT';
    final isHoliday = log.attendanceStatus == 'HOLIDAY' ||
        log.attendanceStatus == 'WEEKEND' ||
        log.attendanceStatus == 'PUBLIC_HOLIDAY' ||
        log.attendanceStatus == 'WEEKLY_OFF' ||
        log.attendanceStatus.contains('HOLIDAY') ||
        log.attendanceStatus.contains('WEEKEND');
    final isLeave = log.attendanceStatus == 'LEAVE' ||
        log.attendanceStatus.contains('LEAVE') ||
        log.attendanceStatus.contains('VACATION');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        List<Widget> buildRestOfActions() {
          if (log.isDisabledAction != 0) return const [];
          if (isAbsent) {
            return [
              _buildActionItem(
                icon: Icons.beach_access_rounded,
                title: 'إجازة',
                subtitle: 'تسجيل إجازة للموظف من قائمة أنواع الإجازات',
                iconColor: const Color(0xFF8B5CF6),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showLeaveTypesSelection(context, log);
                },
              ),
              _buildActionItem(
                icon: Icons.business_center_rounded,
                title: 'مأمورية عمل',
                subtitle: 'تسجيل خروج عمل رسمي خارج مقر الشركة',
                iconColor: const Color(0xFF06B6D4),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showMissionDialog(context, log);
                },
              ),
              _buildActionItem(
                icon: Icons.no_accounts_rounded,
                title: 'غياب بدون عذر',
                subtitle: 'تسجيل غياب اعتيادي بدون إذن مسبق',
                iconColor: const Color(0xFFEF4444),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showAbsenceDialog(context, log);
                },
              ),
              _buildActionItem(
                icon: Icons.access_time_rounded,
                title: 'استئذان',
                subtitle: 'تسجيل استئذان للغياب أو الحضور اليوم',
                iconColor: const Color(0xFF3B82F6),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showWorkPermitDialog(context, log, 'PERMISSION');
                },
              ),
              _buildActionItem(
                icon: Icons.campaign_rounded,
                title: 'استدعاء',
                subtitle: 'تسجيل استدعاء للموظف اليوم',
                iconColor: const Color(0xFFE55B5F),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showWorkPermitDialog(context, log, 'RECALL');
                },
              ),
            ];
          } else if (isLeave) {
            return [
              _buildActionItem(
                icon: Icons.campaign_rounded,
                title: 'استدعاء الموظف',
                subtitle: 'تسجيل استدعاء للموظف من الإجازة',
                iconColor: const Color(0xFFE55B5F),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showWorkPermitDialog(context, log, 'RECALL');
                },
              ),
            ];
          } else if (isHoliday) {
            return [
              _buildActionItem(
                icon: Icons.more_time_rounded,
                title: 'إضافي بدل يعوض',
                subtitle: 'احتساب الوقت الإضافي كتعويض للموظف',
                iconColor: const Color(0xFF10B981),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showOvertimeDialog(context, log);
                },
              ),
              _buildActionItem(
                icon: Icons.more_time_rounded,
                title: 'ساعات إضافية أجر',
                subtitle: 'تسجيل ساعات عمل إضافية بأجر للموظف',
                iconColor: const Color(0xFFF59E0B),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showPaidOvertimeDialog(context, log);
                },
              ),
              _buildActionItem(
                icon: Icons.campaign_rounded,
                title: 'استدعاء الموظف',
                subtitle: 'تسجيل استدعاء للموظف من يوم الراحة',
                iconColor: const Color(0xFFE55B5F),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showWorkPermitDialog(context, log, 'RECALL');
                },
              ),
            ];
          } else {
            // isPresence
            return [
              _buildActionItem(
                icon: Icons.more_time_rounded,
                title: 'إضافي بدل يعوض',
                subtitle: 'احتساب الوقت الإضافي كتعويض للموظف',
                iconColor: const Color(0xFF10B981),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showOvertimeDialog(context, log);
                },
              ),
              _buildActionItem(
                icon: Icons.more_time_rounded,
                title: 'ساعات إضافية أجر',
                subtitle: 'تسجيل ساعات عمل إضافية بأجر للموظف',
                iconColor: const Color(0xFFF59E0B),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showPaidOvertimeDialog(context, log);
                },
              ),
              _buildActionItem(
                icon: Icons.access_time_rounded,
                title: 'تصريح عمل',
                subtitle: 'تسجيل تصريح عمل رسمي لحالة الحضور',
                iconColor: const Color(0xFF3B82F6),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showPresencePermitConfirmationDialog(context, log);
                },
              ),
              _buildActionItem(
                icon: Icons.beach_access_rounded,
                title: 'إجازة',
                subtitle: 'تسجيل إجازة للموظف من قائمة أنواع الإجازات',
                iconColor: const Color(0xFF8B5CF6),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showLeaveTypesSelection(context, log);
                },
              ),
            ];
          }
        }

        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4.5,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isHoliday
                        ? 'اتخاذ إجراء يوم راحة'
                        : (isAbsent
                            ? 'اتخاذ إجراء غياب'
                            : (isLeave ? 'اتخاذ إجراء إجازة' : 'اتخاذ إجراء حضور')),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        log.employeeCode,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            log.nameAr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            log.departmentName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: log.cto != null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildActionItem(
                              icon: Icons.cancel_schedule_send_rounded,
                              title: 'إلغاء بدل يعوض',
                              subtitle: 'إلغاء ساعات التعويض الحالية (${log.cto!.hours} ساعات)',
                              iconColor: const Color(0xFFEF4444),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _showCancelCtoDialog(context, log);
                              },
                            ),
                            ...buildRestOfActions(),
                          ],
                        )
                      : (log.overtime != null && log.isOvertimeEditable
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildActionItem(
                                  icon: Icons.edit_calendar_rounded,
                                  title: 'تعديل إضافي أجر',
                                  subtitle: 'تعديل مواعيد الساعات الإضافية الحالية (${log.overtime!.fromTime} - ${log.overtime!.toTime})',
                                  iconColor: Colors.orange,
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _showEditOvertimeDialog(context, log);
                                  },
                                ),
                                _buildActionItem(
                                  icon: Icons.delete_forever_rounded,
                                  title: 'إلغاء إضافي أجر',
                                  subtitle: 'إلغاء الساعات الإضافية المسجلة اليوم للموظف',
                                  iconColor: Colors.red,
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _showCancelOvertimeWarningDialog(context, log);
                                  },
                                ),
                                ...buildRestOfActions(),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: buildRestOfActions(),
                            )),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 0.8),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textSecondary,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.textSecondary,
                size: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyAction(
    BuildContext context,
    _DailyLog log,
    String statusAr,
    String statusEn,
    String attendanceStatus,
  ) {
    
    // Update local state
    final index = _allLogs.indexWhere((l) => l.employeeId == log.employeeId);
    if (index != -1) {
      setState(() {
        _allLogs[index] = _DailyLog(
          employeeId: log.employeeId,
          employeeCode: log.employeeCode,
          nameAr: log.nameAr,
          nameEn: log.nameEn,
          departmentName: log.departmentName,
          checkInTime: log.checkInTime,
          checkOutTime: log.checkOutTime,
          workingHours: log.workingHours,
          attendanceStatus: attendanceStatus,
          statusAr: statusAr,
          statusEn: statusEn,
          date: log.date,
          isDisabledAction: 1,
        );
      });
    }

    // Show success snack bar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم تطبيق إجراء ($statusAr) للموظف: ${log.nameAr}',
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12.5),
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    // Refresh data from server
    _loadAttendanceForDate(_selectedDate);
  }

  void _showOvertimeDialog(BuildContext context, _DailyLog log) {
    final hoursController = TextEditingController(text: '4');
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.more_time_rounded,
                      color: Color(0xFF10B981),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'تسجيل وقت إضافي',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'الموظف: ${log.nameAr}',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                     TextFormField(
                      controller: hoursController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: false,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'يرجى إدخال عدد الساعات';
                        }
                        if (double.tryParse(val) == null) {
                          return 'يرجى إدخال رقم صحيح';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'عدد الساعات',
                        hintText: 'مثال: 4',
                        prefixIcon: Icon(Icons.access_time_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'الملاحظات',
                        hintText: 'مثال: ساعات إضافية يوم الجمعة',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() {
                              isSubmitting = true;
                            });
                            
                            final success = await _submitOvertime(
                              context,
                              log: log,
                              hours: double.parse(hoursController.text.trim()),
                              notes: notesController.text.trim(),
                            );
                            
                            if (success && context.mounted) {
                              Navigator.pop(dialogContext); // Close dialog
                              if (log.attendanceStatus == 'ABSENT' || log.attendanceStatus == 'NOT_PRESENT') {
                                _applyAction(
                                  context,
                                  log,
                                  'بدل يعوض',
                                  'Compensatory Leave',
                                  'LEAVE',
                                );
                              } else {
                                _applyAction(
                                  context,
                                  log,
                                  'إضافي بدل يعوض',
                                  'Compensatory Overtime',
                                  'COMPLETE',
                                );
                              }
                            } else {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'تأكيد',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _submitPaidOvertime(
    BuildContext context, {
    required _DailyLog log,
    required TimeOfDay fromTime,
    required TimeOfDay toTime,
    required String notes,
  }) async {
    try {
      final formattedDate =
          '${log.date.day.toString().padLeft(2, '0')}/${log.date.month.toString().padLeft(2, '0')}/${log.date.year}';
      
      final fromStr = '${fromTime.hour.toString().padLeft(2, '0')}:${fromTime.minute.toString().padLeft(2, '0')}';
      final toStr = '${toTime.hour.toString().padLeft(2, '0')}:${toTime.minute.toString().padLeft(2, '0')}';

      final requestBody = {
        'employeeId': log.employeeId,
        'overtimeDate': formattedDate,
        'fromTime': fromStr,
        'toTime': toStr,
        'notes': notes.isNotEmpty ? notes : 'اجتماع طارئ مع العملاء',
      };

      final url = '${AppConfig.baseUrl}/MyEmployees/Overtime';
      final response = await ApiClient.post(url, body: requestBody);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        return true;
      } else {
        final errorMsg = responseData['messageAr'] ?? 'فشل تسجيل الساعات الإضافية';
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorMsg,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('Error submitting paid overtime: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'حدث خطأ أثناء الاتصال بالخادم',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  void _showPaidOvertimeDialog(BuildContext context, _DailyLog log) {
    TimeOfDay fromTime = const TimeOfDay(hour: 16, minute: 0);
    TimeOfDay toTime = const TimeOfDay(hour: 20, minute: 0);
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final fromText = '${fromTime.hour.toString().padLeft(2, '0')}:${fromTime.minute.toString().padLeft(2, '0')}';
            final toText = '${toTime.hour.toString().padLeft(2, '0')}:${toTime.minute.toString().padLeft(2, '0')}';

            return AlertDialog(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.more_time_rounded,
                      color: Color(0xFFF59E0B),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'ساعات إضافية أجر',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'الموظف: ${log.nameAr}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: isSubmitting
                                  ? null
                                  : () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: fromTime,
                                      );
                                      if (picked != null) {
                                        setDialogState(() {
                                          fromTime = picked;
                                        });
                                      }
                                    },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'من وقت (البدء)',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                child: Text(
                                  fromText,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: isSubmitting
                                  ? null
                                  : () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: toTime,
                                      );
                                      if (picked != null) {
                                        setDialogState(() {
                                          toTime = picked;
                                        });
                                      }
                                    },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'إلى وقت (الانتهاء)',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                child: Text(
                                  toText,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'الملاحظات',
                          hintText: 'مثال: اجتماع طارئ مع العملاء',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() {
                              isSubmitting = true;
                            });

                            final success = await _submitPaidOvertime(
                              context,
                              log: log,
                              fromTime: fromTime,
                              toTime: toTime,
                              notes: notesController.text.trim(),
                            );

                            if (success && context.mounted) {
                              Navigator.pop(dialogContext); // Close dialog
                              _applyAction(
                                context, // This is actions sheetContext
                                log,
                                'إضافي أجر',
                                'Paid Overtime',
                                'COMPLETE',
                              );
                            } else {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'تأكيد',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _submitOvertime(
    BuildContext context, {
    required _DailyLog log,
    required double hours,
    required String notes,
  }) async {
    try {
      final companyId = await AuthStorage.getCompanyId() ?? 2;
      final branchId = await AuthStorage.getBranchId() ?? 10;
      
      final formattedDate =
          '${log.date.day.toString().padLeft(2, '0')}-${log.date.month.toString().padLeft(2, '0')}-${log.date.year}';
      
      final requestBody = {
        'employeeId': log.employeeId,
        'companyId': companyId,
        'branchId': branchId,
        'ctoDate': formattedDate,
        'ctoHours': hours,
        'ctoTransactionTypeId': 1,
        'notes': notes.isNotEmpty ? notes : 'ساعات إضافية',
      };
      
      final url = '${AppConfig.baseUrl}/MyEmployees/Additional';
      final response = await ApiClient.post(url, body: requestBody);
      
      final responseData = jsonDecode(response.body);
      
      if (response.statusCode == 200 && responseData['status'] == 'success') {
        return true;
      } else {
        final errorMsg = responseData['messageAr'] ?? 'فشل إضافة ساعات إضافية';
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorMsg,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('Error submitting overtime: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'حدث خطأ أثناء الاتصال بالخادم',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  void _showPresencePermitConfirmationDialog(BuildContext context, _DailyLog log) {
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.access_time_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'تسجيل تصريح عمل',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'الموظف: ${log.nameAr}',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'هل أنت متأكد من تسجيل تصريح عمل للموظف اليوم؟ (المدة الافتراضية: ٣٠ دقيقة)',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() {
                            isSubmitting = true;
                          });

                          final success = await _submitWorkPermit(
                            context,
                            log: log,
                            notes: 'تصريح عمل حضور',
                            permitType: 'PERMISSION',
                            durationMinutes: 30,
                          );

                          if (success && context.mounted) {
                            Navigator.pop(dialogContext); // Close dialog
                            _applyAction(
                              context,
                              log,
                              'تصريح عمل',
                              'PERMISSION',
                              'COMPLETE',
                            );
                          } else {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'تأكيد',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showWorkPermitDialog(BuildContext context, _DailyLog log, String permitType) {
    final notesController = TextEditingController();
    final durationController = TextEditingController(text: permitType == 'PERMISSION' ? '30' : '');
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    final isPermission = permitType == 'PERMISSION';
    final title = isPermission ? 'تسجيل استئذان' : 'تسجيل استدعاء';
    final dialogIcon = isPermission ? Icons.access_time_rounded : Icons.campaign_rounded;
    final hintNotes = isPermission ? 'مثال: موعد طبي' : 'مثال: اجتماع طارئ';
    final actionLabel = isPermission ? 'استئذان' : 'استدعاء';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      dialogIcon,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'الموظف: ${log.nameAr}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (isPermission) ...[
                        TextFormField(
                          controller: durationController,
                          keyboardType: TextInputType.number,
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'يرجى إدخال المدة بالدقائق';
                            }
                            final numVal = int.tryParse(val);
                            if (numVal == null || numVal <= 0) {
                              return 'يرجى إدخال رقم صحيح أكبر من الصفر';
                            }
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'المدة بالدقائق',
                            hintText: 'مثال: ٣٠',
                            prefixIcon: Icon(Icons.timer_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: notesController,
                        maxLines: 3,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'يرجى إدخال الملاحظات أو السبب';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: 'الملاحظات / السبب',
                          hintText: hintNotes,
                          prefixIcon: const Icon(Icons.notes_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() {
                              isSubmitting = true;
                            });

                            final duration = isPermission
                                ? int.tryParse(durationController.text.trim())
                                : null;

                            final success = await _submitWorkPermit(
                              context,
                              log: log,
                              notes: notesController.text.trim(),
                              permitType: permitType,
                              durationMinutes: duration,
                            );

                            if (success && context.mounted) {
                              Navigator.pop(dialogContext); // Close dialog
                              _applyAction(
                                context, // This is sheetContext
                                log,
                                actionLabel,
                                permitType,
                                'COMPLETE',
                              );
                            } else {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'تأكيد',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _submitWorkPermit(
    BuildContext context, {
    required _DailyLog log,
    required String notes,
    required String permitType,
    int? durationMinutes,
  }) async {
    try {
      final formattedDate =
          '${log.date.day.toString().padLeft(2, '0')}/${log.date.month.toString().padLeft(2, '0')}/${log.date.year}';

      final requestBody = {
        'employeeId': log.employeeId,
        'permitDate': formattedDate,
        'permitType': permitType,
        'durationMinutes': ?durationMinutes,
        'notes': notes,
      };

      final url = '${AppConfig.baseUrl}/MyEmployees/Workpermits';
      final response = await ApiClient.post(url, body: requestBody);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        return true;
      } else {
        final errorMsg = responseData['messageAr'] ?? 'فشل إضافة الطلب';
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorMsg,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('Error submitting work permit: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'حدث خطأ أثناء الاتصال بالخادم',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  void _showMissionDialog(BuildContext context, _DailyLog log) {
    final destinationController = TextEditingController();
    final purposeController = TextEditingController();
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    DateTime startDateTime = log.date;
    DateTime endDateTime = log.date;
    int? selectedMissionTypeId = _missionTypes.isNotEmpty ? (_missionTypes[0]['id'] as int) : null;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final startText =
                '${startDateTime.day.toString().padLeft(2, '0')}/${startDateTime.month.toString().padLeft(2, '0')}/${startDateTime.year}';
            final endText =
                '${endDateTime.day.toString().padLeft(2, '0')}/${endDateTime.month.toString().padLeft(2, '0')}/${endDateTime.year}';

            return AlertDialog(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.business_center_rounded,
                      color: Color(0xFF06B6D4),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'تسجيل مأمورية عمل',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'الموظف: ${log.nameAr}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: isSubmitting
                                  ? null
                                  : () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: startDateTime,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) {
                                        setDialogState(() {
                                          startDateTime = picked;
                                          if (endDateTime.isBefore(startDateTime)) {
                                            endDateTime = startDateTime;
                                          }
                                        });
                                      }
                                    },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'تاريخ البدء',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                child: Text(
                                  startText,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: isSubmitting
                                  ? null
                                  : () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: endDateTime,
                                        firstDate: startDateTime,
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) {
                                        setDialogState(() {
                                          endDateTime = picked;
                                        });
                                      }
                                    },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'تاريخ الانتهاء',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                child: Text(
                                  endText,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: selectedMissionTypeId,
                        decoration: const InputDecoration(
                          labelText: 'نوع المأمورية',
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        items: _missionTypes.map((type) {
                          return DropdownMenuItem<int>(
                            value: type['id'] as int,
                            child: Text(
                              type['nameAr']?.toString() ?? '',
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: isSubmitting
                            ? null
                            : (val) {
                                if (val != null) {
                                  setDialogState(() {
                                    selectedMissionTypeId = val;
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: destinationController,
                        decoration: const InputDecoration(
                          labelText: 'الوجهة (المكان) - اختياري',
                          hintText: 'مثال: الإسكندرية',
                          prefixIcon: Icon(Icons.location_on_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: purposeController,
                        decoration: const InputDecoration(
                          labelText: 'الغرض من المأمورية - اختياري',
                          hintText: 'مثال: متابعة مشروع الفرع الجديد',
                          prefixIcon: Icon(Icons.description_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظات إضافية',
                          hintText: 'اختياري',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            if (selectedMissionTypeId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'الرجاء اختيار نوع المأمورية أولاً',
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
                                  ),
                                  backgroundColor: AppColors.error,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              return;
                            }
                            setDialogState(() {
                              isSubmitting = true;
                            });
                            
                            final success = await _submitMission(
                              context,
                              log: log,
                              startDate: startDateTime,
                              endDate: endDateTime,
                              missionTypeId: selectedMissionTypeId!,
                              destination: destinationController.text.trim(),
                              purpose: purposeController.text.trim(),
                              notes: notesController.text.trim(),
                            );
                            
                            if (success && context.mounted) {
                              Navigator.pop(dialogContext); // Close dialog
                              _applyAction(
                                context, // This is sheetContext
                                log,
                                'مأمورية',
                                'Business Mission',
                                'COMPLETE',
                              );
                            } else {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06B6D4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'تأكيد',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _submitMission(
    BuildContext context, {
    required _DailyLog log,
    required DateTime startDate,
    required DateTime endDate,
    required int missionTypeId,
    required String destination,
    required String purpose,
    required String notes,
  }) async {
    try {
      final formattedStartDate =
          '${startDate.day.toString().padLeft(2, '0')}/${startDate.month.toString().padLeft(2, '0')}/${startDate.year}';
      final formattedEndDate =
          '${endDate.day.toString().padLeft(2, '0')}/${endDate.month.toString().padLeft(2, '0')}/${endDate.year}';
      
      final requestBody = {
        'employeeId': log.employeeId,
        'startDate': formattedStartDate,
        'endDate': formattedEndDate,
        'missionTypeId': missionTypeId,
        'destination': destination,
        'missionPurpose': purpose,
        'notes': notes,
      };
      
      final url = '${AppConfig.baseUrl}/MyEmployees/Missions';
      final response = await ApiClient.post(url, body: requestBody);
      
      final responseData = jsonDecode(response.body);
      
      if (response.statusCode == 200 && responseData['status'] == 'success') {
        return true;
      } else {
        final errorMsg = responseData['messageAr'] ?? 'فشل إضافة مأمورية عمل';
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorMsg,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('Error submitting mission: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'حدث خطأ أثناء الاتصال بالخادم',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _submitAbsence(
    BuildContext context, {
    required _DailyLog log,
    required String reason,
    required String notes,
  }) async {
    try {
      final formattedDate =
          '${log.date.day.toString().padLeft(2, '0')}/${log.date.month.toString().padLeft(2, '0')}/${log.date.year}';

      final requestBody = {
        'employeeId': log.employeeId,
        'absenceDate': formattedDate,
        'endDate': formattedDate,
        'absenceReason': reason,
        'notes': notes,
      };

      final url = '${AppConfig.baseUrl}/MyEmployees/Absence';
      final response = await ApiClient.post(url, body: requestBody);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        return true;
      } else {
        final errorMsg = responseData['messageAr'] ?? 'فشل تسجيل الغياب';
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorMsg,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('Error submitting absence: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'حدث خطأ أثناء الاتصال بالخادم',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  Future<int?> _fetchAbsenceDays(int employeeId, int year) async {
    try {
      final url = '${AppConfig.baseUrl}/MyEmployees/CountDaysAbsence?employee_id=$employeeId&year=$year';
      final response = await ApiClient.get(url);
      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final absence = responseData['absence'];
        if (absence != null && absence['absenceDays'] != null) {
          return int.tryParse(absence['absenceDays'].toString());
        }
      }
    } catch (e) {
      debugPrint('Error fetching absence days: $e');
    }
    return null;
  }

  void _showAbsenceDialog(BuildContext context, _DailyLog log) {
    final reasonController = TextEditingController(text: 'غياب بدون إذن');
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    // Absence Days local state
    int? absenceDays;
    bool isLoadingAbsence = true;
    bool hasTriggeredFetch = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!hasTriggeredFetch) {
              hasTriggeredFetch = true;
              _fetchAbsenceDays(log.employeeId, log.date.year).then((days) {
                setDialogState(() {
                  absenceDays = days;
                  isLoadingAbsence = false;
                });
              }).catchError((_) {
                setDialogState(() {
                  isLoadingAbsence = false;
                });
              });
            }

            final dateText =
                '${log.date.day.toString().padLeft(2, '0')}/${log.date.month.toString().padLeft(2, '0')}/${log.date.year}';

            return AlertDialog(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.no_accounts_rounded,
                      color: Color(0xFFEF4444),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'تسجيل غياب',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'الموظف: ${log.nameAr}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'التاريخ: $dateText',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border, width: 0.8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isLoadingAbsence
                                    ? 'جاري تحميل إجمالي الغياب...'
                                    : absenceDays != null
                                        ? 'إجمالي أيام الغياب لهذا العام (${log.date.year}): $absenceDays يوم'
                                        : 'إجمالي أيام الغياب: غير متوفر',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isLoadingAbsence
                                      ? AppColors.textSecondary
                                      : absenceDays != null
                                          ? const Color(0xFFEF4444)
                                          : AppColors.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: reasonController,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'يرجى إدخال سبب الغياب';
                          }
                          return null;
                        },
                        decoration: const InputDecoration(
                          labelText: 'سبب الغياب',
                          prefixIcon: Icon(Icons.help_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظات إضافية (اختياري)',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() {
                              isSubmitting = true;
                            });

                            final success = await _submitAbsence(
                              context,
                              log: log,
                              reason: reasonController.text.trim(),
                              notes: notesController.text.trim(),
                            );

                            if (success && context.mounted) {
                              Navigator.pop(dialogContext); // Close dialog
                              _applyAction(
                                context, // This is actions sheetContext
                                log,
                                'غياب',
                                'Absent',
                                'ABSENT',
                              );
                            } else {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'تأكيد',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _submitLeaveRequest(
    BuildContext context, {
    required _DailyLog log,
    required Map<String, dynamic> leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required double totalDays,
  }) async {
    try {
      final formattedStartDate =
          '${startDate.day.toString().padLeft(2, '0')}/${startDate.month.toString().padLeft(2, '0')}/${startDate.year}';
      final formattedEndDate =
          '${endDate.day.toString().padLeft(2, '0')}/${endDate.month.toString().padLeft(2, '0')}/${endDate.year}';

      final requestBody = {
        'employeeId': log.employeeId,
        'leaveTypeId': leaveType['id'],
        'startDate': formattedStartDate,
        'endDate': formattedEndDate,
        'totalDays': totalDays,
      };

      final url = '${AppConfig.baseUrl}/MyEmployees/leaveRequests';
      final response = await ApiClient.post(url, body: requestBody);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        return true;
      } else {
        final errorMsg = responseData['messageAr'] ?? 'فشل تقديم طلب الإجازة';
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorMsg,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('Error submitting leave request: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'حدث خطأ أثناء الاتصال بالخادم',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  Future<double?> _fetchLeaveBalance(int employeeId, int leaveTypeId, int year) async {
    try {
      final url = '${AppConfig.baseUrl}/MyEmployees/LeaveBalance?employee_id=$employeeId&leave_type_id=$leaveTypeId&year=$year';
      final response = await ApiClient.get(url);
      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final balance = responseData['balance'];
        if (balance != null && balance['remaining'] != null) {
          return double.tryParse(balance['remaining'].toString());
        }
      }
    } catch (e) {
      debugPrint('Error fetching leave balance: $e');
    }
    return null;
  }

  void _showLeaveRequestDialog(
    BuildContext context, {
    required _DailyLog log,
    required Map<String, dynamic> leaveType,
  }) {
    DateTime startDateTime = DateTime(log.date.year, log.date.month, log.date.day);
    DateTime endDateTime = DateTime(log.date.year, log.date.month, log.date.day);
    
    final isPresent = log.attendanceStatus == 'COMPLETE' ||
        log.attendanceStatus == 'NO_CHECKOUT' ||
        log.attendanceStatus == 'PRESENT' ||
        log.attendanceStatus.startsWith('PRESENT') ||
        log.checkInTime != null;

    double totalDays = isPresent ? 0.5 : 1.0;
    final daysController = TextEditingController(text: isPresent ? '0.5' : '1');
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    // Leave Balance local state
    double? leaveBalance;
    bool isLoadingBalance = true;
    bool hasTriggeredFetch = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!hasTriggeredFetch) {
              hasTriggeredFetch = true;
              _fetchLeaveBalance(log.employeeId, leaveType['id'], log.date.year).then((balance) {
                setDialogState(() {
                  leaveBalance = balance;
                  isLoadingBalance = false;
                });
              }).catchError((_) {
                setDialogState(() {
                  isLoadingBalance = false;
                });
              });
            }

            final startText =
                '${startDateTime.day.toString().padLeft(2, '0')}/${startDateTime.month.toString().padLeft(2, '0')}/${startDateTime.year}';
            final endText =
                '${endDateTime.day.toString().padLeft(2, '0')}/${endDateTime.month.toString().padLeft(2, '0')}/${endDateTime.year}';

            return AlertDialog(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.beach_access_rounded,
                      color: Color(0xFF8B5CF6),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'تسجيل طلب إجازة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'الموظف: ${log.nameAr}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'نوع الإجازة: ${leaveType['nameAr']}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border, width: 0.8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_rounded,
                              size: 16,
                              color: Color(0xFF8B5CF6),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isLoadingBalance
                                    ? 'جاري تحميل رصيد الإجازات...'
                                    : leaveBalance != null
                                        ? 'رصيد الإجازة المتبقي: $leaveBalance يوم'
                                        : 'رصيد الإجازة المتبقي: غير متوفر',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isLoadingBalance
                                      ? AppColors.textSecondary
                                      : leaveBalance != null
                                          ? const Color(0xFF8B5CF6)
                                          : AppColors.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: isPresent
                                  ? null
                                  : () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: startDateTime,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        final cleanPicked = DateTime(picked.year, picked.month, picked.day);
                                        setDialogState(() {
                                          startDateTime = cleanPicked;
                                          if (endDateTime.isBefore(startDateTime)) {
                                            endDateTime = startDateTime;
                                          }
                                          totalDays = endDateTime.difference(startDateTime).inDays + 1.0;
                                          daysController.text = totalDays.toInt().toString();
                                        });
                                      }
                                    },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'تاريخ البدء',
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  enabled: !isPresent,
                                ),
                                child: Text(
                                  startText,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isPresent ? AppColors.textSecondary : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: isPresent
                                  ? null
                                  : () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: endDateTime.isBefore(startDateTime) ? startDateTime : endDateTime,
                                        firstDate: startDateTime,
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        final cleanPicked = DateTime(picked.year, picked.month, picked.day);
                                        setDialogState(() {
                                          endDateTime = cleanPicked;
                                          totalDays = endDateTime.difference(startDateTime).inDays + 1.0;
                                          daysController.text = totalDays.toInt().toString();
                                        });
                                      }
                                    },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'تاريخ الانتهاء',
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  enabled: !isPresent,
                                ),
                                child: Text(
                                  endText,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isPresent ? AppColors.textSecondary : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (isPresent)
                        DropdownButtonFormField<double>(
                          initialValue: totalDays,
                          decoration: const InputDecoration(
                            labelText: 'مدة الإجازة',
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            enabled: false,
                          ),
                          items: const [
                            DropdownMenuItem<double>(
                              value: 0.5,
                              child: Text(
                                'نصف يوم (0.5)',
                                style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                              ),
                            ),
                          ],
                          onChanged: null,
                        )
                      else
                        TextFormField(
                          controller: daysController,
                          keyboardType: TextInputType.number,
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'يرجى إدخال عدد الأيام';
                            }
                            final parsed = int.tryParse(val.trim());
                            if (parsed == null || parsed <= 0) {
                              return 'يرجى إدخال عدد صحيح أكبر من الصفر';
                            }
                            if (leaveBalance != null && parsed > leaveBalance!) {
                              return 'الرصيد غير كافٍ (المتبقي: $leaveBalance)';
                            }
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'عدد الأيام',
                            hintText: 'مثال: ٥',
                            prefixIcon: Icon(Icons.date_range_rounded),
                          ),
                          onChanged: (val) {
                            final days = int.tryParse(val.trim());
                            if (days != null && days > 0) {
                              setDialogState(() {
                                totalDays = days.toDouble();
                                endDateTime = startDateTime.add(Duration(days: days - 1));
                              });
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            if (leaveBalance != null && totalDays > leaveBalance!) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'رصيد الإجازات المتبقي غير كافٍ (الرصيد المتاح: $leaveBalance يوم)',
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
                                  ),
                                  backgroundColor: AppColors.error,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              return;
                            }
                            setDialogState(() {
                              isSubmitting = true;
                            });

                            final success = await _submitLeaveRequest(
                              context,
                              log: log,
                              leaveType: leaveType,
                              startDate: startDateTime,
                              endDate: endDateTime,
                              totalDays: totalDays,
                            );

                            if (success && context.mounted) {
                              Navigator.pop(dialogContext); // Close dialog
                              _applyAction(
                                context, // This is outer sheetContext
                                log,
                                leaveType['nameAr'],
                                leaveType['nameEn'],
                                'LEAVE',
                              );
                            } else {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'تأكيد',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _loadLeaveTypes({VoidCallback? onLoaded}) async {
    try {
      final url = '${AppConfig.baseUrl}/Leave/LeaveType';
      final response = await ApiClient.get(url);
      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final List<dynamic> types = responseData['leaveTypes'] ?? [];
        if (mounted) {
          setState(() {
            _leaveTypes = types.map((t) => {
              'id': t['id'],
              'nameAr': t['nameAr']?.toString() ?? '',
              'nameEn': t['nameEn']?.toString() ?? '',
            }).toList();
          });
        }
        if (onLoaded != null) {
          onLoaded();
        }
      }
    } catch (e) {
      debugPrint('Error loading leave types: $e');
    }
  }

  Future<void> _loadMissionTypes() async {
    try {
      final url = '${AppConfig.baseUrl}/MyEmployees/MissionType';
      final response = await ApiClient.get(url);
      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final List<dynamic> types = responseData['missionTypes'] ?? [];
        if (mounted) {
          setState(() {
            _missionTypes = types.map((t) => {
              'id': t['id'],
              'nameAr': t['nameAr']?.toString() ?? '',
              'nameEn': t['nameEn']?.toString() ?? '',
              'classification': t['classification']?.toString() ?? '',
            }).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading mission types: $e');
    }
  }

  void _showLeaveTypesSelection(BuildContext context, _DailyLog log) {
    if (_leaveTypes.isEmpty) {
      _loadLeaveTypes();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (_leaveTypes.isEmpty) {
              _loadLeaveTypes(onLoaded: () {
                if (sheetContext.mounted) {
                  setSheetState(() {});
                }
              });
            }

            final isPresent = log.attendanceStatus == 'COMPLETE' ||
                log.attendanceStatus == 'NO_CHECKOUT' ||
                log.attendanceStatus == 'PRESENT' ||
                log.attendanceStatus.startsWith('PRESENT') ||
                log.checkInTime != null;

            final baseTypes = isPresent
                ? _leaveTypes.where((t) => t['id'] == 3).toList()
                : _leaveTypes;

            final isSearchEnabled = baseTypes.isNotEmpty;
            List<Map<String, dynamic>> filteredTypes = baseTypes;
            String searchQuery = '';

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 4.5,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'اختر نوع الإجازة',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  if (isSearchEnabled)
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: TextField(
                        onChanged: (val) {
                          setSheetState(() {
                            searchQuery = val.trim();
                          });
                        },
                        decoration: const InputDecoration(
                          hintText: 'ابحث عن نوع الإجازة...',
                          prefixIcon: Icon(Icons.search_rounded),
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: _leaveTypes.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(color: AppColors.primary),
                                SizedBox(height: 16),
                                Text(
                                  'جاري تحميل أنواع الإجازات...',
                                  style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          )
                        : () {
                            if (searchQuery.isNotEmpty) {
                              final isPresent = log.attendanceStatus == 'COMPLETE' ||
                                  log.attendanceStatus == 'NO_CHECKOUT' ||
                                  log.attendanceStatus == 'PRESENT' ||
                                  log.attendanceStatus.startsWith('PRESENT') ||
                                  log.checkInTime != null;

                              final baseTypes = isPresent
                                  ? _leaveTypes.where((t) => t['id'] == 3).toList()
                                  : _leaveTypes;

                              filteredTypes = baseTypes.where((t) {
                                return t['nameAr']!.contains(searchQuery) ||
                                    t['nameEn']!.toLowerCase().contains(searchQuery.toLowerCase());
                              }).toList();
                            }
                            
                            if (filteredTypes.isEmpty) {
                              return const Center(
                                child: Text(
                                  'لا توجد نتائج مطابقة',
                                  style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary),
                                ),
                              );
                            }
                            
                            return ListView.builder(
                              itemCount: filteredTypes.length,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              itemBuilder: (context, index) {
                                final type = filteredTypes[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.pop(sheetContext); // Close leave types selection
                                      _showLeaveRequestDialog(
                                        context, // This is outer sheetContext
                                        log: log,
                                        leaveType: type,
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppColors.border, width: 0.8),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withValues(alpha: 0.08),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.beach_access_rounded,
                                              color: AppColors.primary,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Text(
                                              type['nameAr'],
                                              style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            color: AppColors.textSecondary,
                                            size: 12,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StatusTabItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final LinearGradient activeGradient;
  final VoidCallback onTap;

  const _StatusTabItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.activeColor,
    required this.activeGradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            gradient: isSelected ? activeGradient : null,
            color: isSelected ? null : AppColors.divider,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyLogTile extends StatelessWidget {
  const _DailyLogTile({
    required this.log,
    this.onTap,
  });

  final _DailyLog log;
  final VoidCallback? onTap;

  Widget _buildSpaciousTimeDetail({
    required IconData icon,
    required String label,
    required String time,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.field,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: iconColor),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpaciousTimings() {
    final status = log.attendanceStatus;
    if (status.contains('HOLIDAY') ||
        status.contains('WEEKEND') ||
        status.contains('PUBLIC_HOLIDAY') ||
        status.contains('WEEKLY_OFF')) {
      return Row(
        children: [
          const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              log.statusAr.isNotEmpty ? log.statusAr : 'عطلة رسمية أو راحة أسبوعية',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      );
    }

    if (status.contains('LEAVE') || status.contains('VACATION')) {
      return Row(
        children: [
          const Icon(Icons.beach_access_rounded, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              log.statusAr.isNotEmpty ? log.statusAr : 'إجازة للموظف',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      );
    }

    if (status.contains('ABSENT') || status.contains('NOT_PRESENT')) {
      return Row(
        children: [
          const Icon(Icons.cancel_outlined, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              log.statusAr.isNotEmpty ? log.statusAr : 'الموظف غائب عن العمل اليوم',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildSpaciousTimeDetail(
          icon: Icons.login_rounded,
          label: 'دخول',
          time: log.checkInTime ?? '--:--',
          iconColor: Colors.green,
        ),
        _buildSpaciousTimeDetail(
          icon: Icons.logout_rounded,
          label: 'خروج',
          time: log.checkOutTime ?? '--:--',
          iconColor: Colors.orange,
        ),
        if (log.workingHours != null)
          _buildSpaciousTimeDetail(
            icon: Icons.access_time_rounded,
            label: 'ساعات',
            time: '${log.workingHours} س',
            iconColor: AppColors.primary,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Color badgeBg;
    Color badgeText;
    String statusName = log.statusAr.isNotEmpty ? log.statusAr : 'غير محدد';

    final String status = log.attendanceStatus;
    if (status.contains('COMPLETE')) {
      badgeBg = const Color(0xFFE8F5E9); // Light green
      badgeText = const Color(0xFF2E7D32); // Dark green
    } else if (status.contains('NO_CHECKOUT')) {
      badgeBg = const Color(0xFFFFF3E0); // Light orange/amber
      badgeText = const Color(0xFFE65100); // Dark orange
    } else if (status.contains('ABSENT') || status.contains('NOT_PRESENT')) {
      badgeBg = const Color(0xFFFFEBEE); // Light red
      badgeText = const Color(0xFFC62828); // Dark red
    } else if (status.contains('LEAVE') || status.contains('VACATION')) {
      badgeBg = const Color(0xFFE3F2FD); // Light blue
      badgeText = const Color(0xFF1565C0); // Dark blue
    } else if (status.contains('HOLIDAY') ||
        status.contains('WEEKEND') ||
        status.contains('PUBLIC_HOLIDAY') ||
        status.contains('WEEKLY_OFF')) {
      badgeBg = const Color(0xFFF3E5F5); // Light purple
      badgeText = const Color(0xFF6A1B9A); // Dark purple
    } else {
      badgeBg = const Color(0xFFECEFF1); // Light grey
      badgeText = const Color(0xFF37474F); // Dark grey
    }

    final bool showStatusBadge = !status.contains('LEAVE') &&
        !status.contains('VACATION') &&
        !status.contains('ABSENT') &&
        !status.contains('NOT_PRESENT') &&
        !status.contains('HOLIDAY') &&
        !status.contains('WEEKEND') &&
        !status.contains('PUBLIC_HOLIDAY') &&
        !status.contains('WEEKLY_OFF');

    final bool isHoliday = log.attendanceStatus == 'HOLIDAY' ||
        log.attendanceStatus == 'WEEKEND' ||
        log.attendanceStatus == 'PUBLIC_HOLIDAY' ||
        log.attendanceStatus == 'WEEKLY_OFF' ||
        log.attendanceStatus.contains('HOLIDAY') ||
        log.attendanceStatus.contains('WEEKEND');

    final bool isLeave = log.attendanceStatus == 'LEAVE' ||
        log.attendanceStatus.contains('LEAVE') ||
        log.attendanceStatus.contains('VACATION');

    final bool isEditableOvertime = log.overtime != null && log.isOvertimeEditable;
    final bool canConfigure = log.isDisabledAction == 0 ||
        log.cto != null ||
        isEditableOvertime ||
        (isHoliday && log.cto == null && log.overtime == null) ||
        (isLeave && log.cto == null && log.overtime == null);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 1.0),
      ),
      child: InkWell(
        onTap: canConfigure ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Top Section: Code + Name & Department
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Code Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      log.employeeCode,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name & Department
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.nameAr,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            fontSize: 14.5,
                            height: 1.3,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          log.departmentName.trim().isEmpty ? 'أقسام أخرى' : log.departmentName.trim(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: AppColors.divider, height: 1),
              ),

              // 2. Bottom Section: Timings + Status Badge / Action Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Timings/State details
                  Expanded(
                    child: _buildSpaciousTimings(),
                  ),
                  const SizedBox(width: 12),

                  // Status badge and "تسجيل إجراء"
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (showStatusBadge)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusName,
                            style: TextStyle(
                              color: badgeText,
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      if (canConfigure) ...[
                        if (showStatusBadge) const SizedBox(height: 6),
                        if (log.isDisabledAction == 1 && log.cto != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.close_rounded,
                                  size: 12,
                                  color: Colors.red,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'إلغاء بدل يعوض',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (log.isDisabledAction == 1 && isEditableOvertime)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.15)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.edit_calendar_rounded,
                                  size: 12,
                                  color: Colors.orange,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'تعديل الإضافي',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.touch_app_rounded,
                                  size: 12,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'تسجيل إجراء',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_note_rounded,
            size: 48,
            color: AppColors.textSecondary.withValues(alpha: 0.40),
          ),
          const SizedBox(height: 12),
          const Text(
            'لا توجد يوميات مطابقة للبحث',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CtoInfo {
  final int id;
  final int hours;

  const _CtoInfo({
    required this.id,
    required this.hours,
  });

  factory _CtoInfo.fromJson(Map<String, dynamic> json) {
    return _CtoInfo(
      id: json['id'] as int? ?? 0,
      hours: json['hours'] as int? ?? 0,
    );
  }
}

class _OvertimeInfo {
  final int id;
  final String fromTime;
  final String toTime;

  const _OvertimeInfo({
    required this.id,
    required this.fromTime,
    required this.toTime,
  });

  factory _OvertimeInfo.fromJson(Map<String, dynamic> json) {
    return _OvertimeInfo(
      id: json['id'] as int? ?? 0,
      fromTime: json['fromTime']?.toString() ?? '',
      toTime: json['toTime']?.toString() ?? '',
    );
  }
}

class _DailyLog {
  final int employeeId;
  final String employeeCode;
  final String nameAr;
  final String nameEn;
  final String departmentName;
  final String? checkInTime;
  final String? checkOutTime;
  final String? workingHours;
  final String attendanceStatus;
  final String statusAr;
  final String statusEn;
  final DateTime date;
  final int isDisabledAction;
  final _CtoInfo? cto;
  final _OvertimeInfo? overtime;

  const _DailyLog({
    required this.employeeId,
    required this.employeeCode,
    required this.nameAr,
    required this.nameEn,
    required this.departmentName,
    this.checkInTime,
    this.checkOutTime,
    this.workingHours,
    required this.attendanceStatus,
    required this.statusAr,
    required this.statusEn,
    required this.date,
    this.isDisabledAction = 0,
    this.cto,
    this.overtime,
  });

  bool get isOvertimeEditable {
    if (overtime == null) return false;
    try {
      final timeParts = overtime!.fromTime.split(':');
      if (timeParts.length < 2) return false;
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      
      final overtimeStart = DateTime(
        date.year,
        date.month,
        date.day,
        hour,
        minute,
      );
      
      return DateTime.now().isBefore(overtimeStart);
    } catch (e) {
      return false;
    }
  }

  factory _DailyLog.fromJson(Map<String, dynamic> json, DateTime date) {
    return _DailyLog(
      employeeId: json['employeeId'] as int? ?? 0,
      employeeCode: json['employeeCode']?.toString() ?? '',
      nameAr: json['nameAr']?.toString() ?? '',
      nameEn: json['nameEn']?.toString() ?? '',
      departmentName: json['departmentName']?.toString() ?? '',
      checkInTime: json['checkInTime']?.toString(),
      checkOutTime: json['checkOutTime']?.toString(),
      workingHours: json['workingHours']?.toString(),
      attendanceStatus: json['attendanceStatus']?.toString() ?? '',
      statusAr: json['statusAr']?.toString() ?? '',
      statusEn: json['statusEn']?.toString() ?? '',
      date: date,
      isDisabledAction: json['isDisabledAction'] as int? ?? 0,
      cto: json['cto'] != null ? _CtoInfo.fromJson(json['cto'] as Map<String, dynamic>) : null,
      overtime: json['overtime'] != null
          ? _OvertimeInfo.fromJson(json['overtime'] as Map<String, dynamic>)
          : null,
    );
  }
}
