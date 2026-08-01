import 'dart:convert';
import 'package:flutter/material.dart';

import 'home_tab.dart';
import '../../profile/presentation/profile_tab.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimensions.dart';
import '../../../app/app_config.dart';
import '../../../core/network/api_client.dart';

/// App shell wrapping bottom navigation tabs (Home, Employees, Notifications, Profile).
/// Features a custom center FloatingActionButton (+) as shown in the mockup.
class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const HomeTab(),
    const EmployeesTab(),
    const NotificationsTab(),
    const ProfileTab(),
  ];



  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: IndexedStack(index: _currentIndex, children: _tabs),
        bottomNavigationBar: BottomAppBar(
          color: AppColors.surface,
          elevation: 10,
          padding: EdgeInsets.zero,
          child: Container(
            height: 64,
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildNavItem(
                    index: 0,
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_outlined,
                    label: 'الرئيسية',
                  ),
                ),
                Expanded(
                  child: _buildNavItem(
                    index: 1,
                    icon: Icons.people_outline_rounded,
                    activeIcon: Icons.people_outline_rounded,
                    label: 'الموظفين',
                  ),
                ),
                Expanded(
                  child: _buildNavItem(
                    index: 2,
                    icon: Icons.notifications_none_outlined,
                    activeIcon: Icons.notifications_none_outlined,
                    label: 'الإشعارات',
                  ),
                ),
                Expanded(
                  child: _buildNavItem(
                    index: 3,
                    icon: Icons.person_outline_rounded,
                    activeIcon: Icons.person_outline_rounded,
                    label: 'حسابي',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSelected ? activeIcon : icon,
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
            size: AppDimensions.iconMd,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}



/// MOCK TAB: Notifications Tab
class NotificationsTab extends StatelessWidget {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> notificationsList = [
      {
        'title': 'طلب إجازة جديد',
        'subtitle': 'سارة خالد قدمت طلب إجازة سنوية لمدة 3 أيام',
        'time': 'منذ 5 دقائق',
        'icon': 'beach_access_rounded',
      },
      {
        'title': 'تنبيه تأخير دخول',
        'subtitle': 'محمد علي سجّل دخول متأخراً الساعة 9:42 ص',
        'time': 'منذ 20 دقيقة',
        'icon': 'schedule_rounded',
      },
      {
        'title': 'اعتماد كشف المرتبات',
        'subtitle': 'بانتظار موافقتك على كشف المرتبات لشهر مايو',
        'time': 'منذ ساعة',
        'icon': 'account_balance_wallet_outlined',
      },
      {
        'title': 'اجتماع عمل طارئ',
        'subtitle': 'تمت إضافتك لاجتماع مناقشة الميزانية الجديدة',
        'time': 'منذ يوم',
        'icon': 'groups_outlined',
      },
    ];

    IconData getIcon(String iconName) {
      switch (iconName) {
        case 'beach_access_rounded':
          return Icons.beach_access_rounded;
        case 'schedule_rounded':
          return Icons.schedule_rounded;
        case 'account_balance_wallet_outlined':
          return Icons.account_balance_wallet_outlined;
        case 'groups_outlined':
          return Icons.groups_outlined;
        default:
          return Icons.notifications_rounded;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('الإشعارات'), centerTitle: true),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(AppDimensions.spaceMd),
          itemCount: notificationsList.length,
          itemBuilder: (context, i) {
            final n = notificationsList[i];
            return Container(
              margin: const EdgeInsets.only(bottom: AppDimensions.spaceSm + 2),
              padding: const EdgeInsets.all(AppDimensions.spaceSm + 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      getIcon(n['icon']!),
                      color: AppColors.primary,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spaceSm + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n['title']!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          n['subtitle']!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spaceSm),
                  Text(
                    n['time']!,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class EmployeesTab extends StatefulWidget {
  const EmployeesTab({super.key});

  @override
  State<EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<EmployeesTab> {
  bool _isLoading = true;
  String _errorMessage = '';
  List<dynamic> _employees = [];
  Map<String, List<dynamic>> _groupedEmployees = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
  }

  Future<void> _fetchEmployees() async {
    try {
      final url = '${AppConfig.baseUrl}/MyEmployees/Present';
      final response = await ApiClient.get(url);
      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final List<dynamic> list = responseData['attendance'] ?? [];
        if (mounted) {
          setState(() {
            _employees = list;
            _groupAndFilterEmployees();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = responseData['messageAr'] ?? 'فشل جلب بيانات الموظفين';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'حدث خطأ في الاتصال بالشبكة';
          _isLoading = false;
        });
      }
    }
  }

  void _groupAndFilterEmployees() {
    final query = _searchQuery.trim().toLowerCase();
    final Map<String, List<dynamic>> grouped = {};

    for (var emp in _employees) {
      final nameAr = (emp['nameAr'] ?? '').toString();
      final nameEn = (emp['nameEn'] ?? '').toString();
      final code = (emp['employeeCode'] ?? '').toString();
      final dept = (emp['departmentName'] ?? '').toString().trim();
      final deptKey = dept.isEmpty ? 'أقسام أخرى' : dept;

      if (query.isNotEmpty) {
        final matches = nameAr.toLowerCase().contains(query) ||
            nameEn.toLowerCase().contains(query) ||
            code.toLowerCase().contains(query) ||
            deptKey.toLowerCase().contains(query);
        if (!matches) continue;
      }

      if (!grouped.containsKey(deptKey)) {
        grouped[deptKey] = [];
      }
      grouped[deptKey]!.add(emp);
    }

    setState(() {
      _groupedEmployees = grouped;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'دليل الموظفين',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppDimensions.spaceMd),
              child: TextField(
                onChanged: (val) {
                  _searchQuery = val;
                  _groupAndFilterEmployees();
                },
                decoration: const InputDecoration(
                  hintText: 'ابحث عن موظف أو قسم...',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _errorMessage.isNotEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 14.5,
                                    color: AppColors.textSecondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _isLoading = true;
                                      _errorMessage = '';
                                    });
                                    _fetchEmployees();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: const Text(
                                    'إعادة المحاولة',
                                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _groupedEmployees.isEmpty
                          ? const Center(
                              child: Text(
                                'لا يوجد موظفين متطابقين',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceMd),
                              itemCount: _groupedEmployees.length,
                              itemBuilder: (context, index) {
                                final deptName = _groupedEmployees.keys.elementAt(index);
                                final deptEmployees = _groupedEmployees[deptName]!;

                                return Card(
                                  elevation: 0,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: const BorderSide(color: AppColors.border, width: 1.0),
                                  ),
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      leading: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.lan_rounded,
                                          color: AppColors.primary,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        deptName,
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'عدد الموظفين: ${deptEmployees.length}',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      children: [
                                        const Divider(color: AppColors.border, height: 1),
                                        ListView.builder(
                                          shrinkWrap: true,
                                          physics: const NeverScrollableScrollPhysics(),
                                          itemCount: deptEmployees.length,
                                          itemBuilder: (context, i) {
                                            final emp = deptEmployees[i];
                                            final String name = emp['nameAr'] ?? emp['nameEn'] ?? 'موظف';
                                            final String code = emp['employeeCode'] ?? '';

                                            return ListTile(
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              leading: CircleAvatar(
                                                radius: 18,
                                                backgroundColor: AppColors.primary.withValues(alpha: 0.05),
                                                child: Text(
                                                  name.trim().isEmpty ? 'م' : name.trim().split(' ').first[0],
                                                  style: const TextStyle(
                                                    color: AppColors.primary,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              title: Text(
                                                name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.textPrimary,
                                                  fontSize: 12.5,
                                                  fontFamily: 'Cairo',
                                                ),
                                              ),
                                              trailing: Text(
                                                '#$code',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  color: AppColors.textSecondary,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

