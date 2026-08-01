import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../../theme/app_colors.dart';
import '../../../app/app_config.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/utils/attendance_logger.dart';

/// Screen listing trips assigned to the employee ("رحلاتي").
/// Supports filtering by date and status, starting, ending, and cancelling trips.
class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  DateTime _selectedDate = DateTime.now();
  String _activeTab = 'ALL'; // 'ALL', 'NEW', 'STARTED', 'COMPLETED', 'CANCELLED'
  bool _isLoading = true;
  String _errorMessage = '';
  List<dynamic> _allTrips = [];
  bool _isActionInProgress = false;

  @override
  void initState() {
    super.initState();
    unawaited(AttendanceLogger.logScreenActivity('TRIPS'));
    _fetchTrips();
  }

  String _formatDateForApi(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDateForDisplay(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatTimeForDisplay(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return '--:--';
    final parts = dateTimeStr.trim().split(' ');
    final timeStr = parts.length > 1 ? parts[1] : parts[0];
    
    try {
      final timeParts = timeStr.split(':');
      if (timeParts.length >= 2) {
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        final ampm = hour >= 12 ? 'م' : 'ص';
        return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $ampm';
      }
    } catch (_) {}
    return timeStr;
  }

  String _formatDistance(dynamic rawDistance) {
    if (rawDistance == null) return '--';
    try {
      final dist = double.parse(rawDistance.toString());
      if (dist >= 100) {
        return '${(dist / 1000).toStringAsFixed(1)} كم';
      }
      return '$dist كم';
    } catch (_) {}
    return rawDistance.toString();
  }

  Future<void> _fetchTrips() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final token = await AuthStorage.getToken();
      if (token == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'جلسة المستخدم منتهية. يرجى تسجيل الدخول مجدداً.';
        });
        return;
      }

      final dateStr = _formatDateForApi(_selectedDate);
      final url = '${AppConfig.baseUrl}/Trips/MyTrips?date=$dateStr';

      debugPrint('================= [HTTP REQUEST] =================');
      debugPrint('--> GET: $url');
      debugPrint('Headers: {Authorization: Bearer $token}');
      debugPrint('==================================================');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('================= [HTTP RESPONSE] =================');
      debugPrint('<-- Status: ${response.statusCode} | URL: $url');
      debugPrint('Response Body: ${response.body}');
      debugPrint('===================================================');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            _allTrips = data['trips'] ?? [];
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'فشل جلب الرحلات من الخادم.';
      });
    } catch (e) {
      debugPrint('Error fetching trips: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'حدث خطأ في الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.';
      });
    }
  }

  // Helper to filter loaded list locally
  List<dynamic> get _filteredTrips {
    if (_activeTab == 'ALL') return _allTrips;
    return _allTrips.where((trip) => trip['status'] == _activeTab).toList();
  }

  int _getCountForTab(String tab) {
    if (tab == 'ALL') return _allTrips.length;
    return _allTrips.where((trip) => trip['status'] == tab).length;
  }

  Future<Position?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showWarningSnackBar('يرجى تفعيل خدمة الموقع الجغرافي (GPS)');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showWarningSnackBar('صلاحية تحديد الموقع مرفوضة');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showWarningSnackBar('صلاحية الموقع مرفوضة دائماً، يرجى تفعيلها من الإعدادات');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Error getting position: $e');
      return null;
    }
  }

  // --- ACTIONS ---

  Future<void> _startTrip(dynamic trip) async {
    final tripId = trip['id'] ?? trip['tripId'];
    
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('بدء الرحلة', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('هل أنت متأكد من بدء هذه الرحلة الآن؟ سيتم تفعيل التتبع الجغرافي.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('بدء', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isActionInProgress = true;
    });

    final position = await _getCurrentLocation();
    if (position == null) {
      setState(() {
        _isActionInProgress = false;
      });
      return;
    }

    try {
      final token = await AuthStorage.getToken();
      if (token == null) return;

      int isFake = 0;
      try {
        if (position.isMocked) {
          isFake = 1;
        }
      } catch (_) {}

      final url = '${AppConfig.baseUrl}/Trips/StartTripId';
      final body = jsonEncode({
        "tripId": tripId,
        "latitude": position.latitude.toString(),
        "longitude": position.longitude.toString(),
        "isFake": isFake
      });

      debugPrint('================= [HTTP REQUEST] =================');
      debugPrint('--> POST: $url');
      debugPrint('Body: $body');
      debugPrint('==================================================');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      debugPrint('================= [HTTP RESPONSE] =================');
      debugPrint('<-- Status: ${response.statusCode} | Body: ${response.body}');
      debugPrint('===================================================');

      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        _showSuccessSnackBar(data['messageAr'] ?? 'تم بدء الرحلة بنجاح وجاري تتبع خط السير');
        _fetchTrips();
        return;
      } else {
        _showWarningSnackBar(data['messageAr'] ?? 'فشل بدء الرحلة على الخادم.');
        return;
      }
    } catch (e) {
      debugPrint('Error starting trip: $e');
      _showWarningSnackBar('حدث خطأ أثناء بدء الرحلة. يرجى التحقق من الاتصال.');
    } finally {
      setState(() {
        _isActionInProgress = false;
      });
    }
  }

  Future<void> _endTrip(dynamic trip) async {
    final tripId = trip['id'] ?? trip['tripId'];
    final notesController = TextEditingController();

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'إنهاء الرحلة الميدانية',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'يرجى إدخال أي ملاحظات أو نتائج للزيارة قبل الإنهاء (اختياري):',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontFamily: 'Cairo'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesController,
                maxLines: 3,
                style: const TextStyle(fontSize: 13, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  hintText: 'اكتب ملاحظاتك هنا...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(10),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('تأكيد الإنهاء والرفع', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isActionInProgress = true;
    });

    final position = await _getCurrentLocation();
    if (position == null) {
      setState(() {
        _isActionInProgress = false;
      });
      return;
    }

    try {
      final token = await AuthStorage.getToken();
      if (token == null) return;

      int isFake = 0;
      try {
        if (position.isMocked) {
          isFake = 1;
        }
      } catch (_) {}

      final url = '${AppConfig.baseUrl}/Trips/EndTripId';
      final body = jsonEncode({
        "tripId": tripId,
        "latitude": position.latitude.toString(),
        "longitude": position.longitude.toString(),
        "isFake": isFake,
        "notes": notesController.text.trim()
      });

      debugPrint('================= [HTTP REQUEST] =================');
      debugPrint('--> POST: $url');
      debugPrint('Body: $body');
      debugPrint('==================================================');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      debugPrint('================= [HTTP RESPONSE] =================');
      debugPrint('<-- Status: ${response.statusCode} | Body: ${response.body}');
      debugPrint('===================================================');

      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        _showSuccessSnackBar(data['messageAr'] ?? 'تم إنهاء الرحلة بنجاح وحفظ تفاصيل المسار');
        _fetchTrips();
        return;
      } else {
        _showWarningSnackBar(data['messageAr'] ?? 'فشل إنهاء الرحلة على الخادم.');
        return;
      }
    } catch (e) {
      debugPrint('Error ending trip: $e');
      _showWarningSnackBar('حدث خطأ أثناء إنهاء الرحلة. يرجى التحقق من الاتصال.');
    } finally {
      setState(() {
        _isActionInProgress = false;
      });
    }
  }

  Future<void> _cancelTrip(dynamic trip) async {
    final tripId = trip['id'] ?? trip['tripId'];
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
              SizedBox(width: 8),
              Text('إلغاء الرحلة الميدانية', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'يرجى إدخال سبب الإلغاء (إلزامي):',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: reasonController,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13, fontFamily: 'Cairo'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'سبب الإلغاء مطلوب إجبارياً';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    hintText: 'اكتب سبب الإلغاء هنا...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(10),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('تراجع', style: TextStyle(fontFamily: 'Cairo')),
            ),
            TextButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('إلغاء الرحلة', style: TextStyle(color: AppColors.error, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isActionInProgress = true;
    });

    try {
      final token = await AuthStorage.getToken();
      if (token == null) return;

      final url = '${AppConfig.baseUrl}/Trips/CancelTripId';
      final body = jsonEncode({
        "tripId": tripId,
        "cancelledReason": reasonController.text.trim()
      });

      debugPrint('================= [HTTP REQUEST] =================');
      debugPrint('--> POST: $url');
      debugPrint('Body: $body');
      debugPrint('==================================================');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      debugPrint('================= [HTTP RESPONSE] =================');
      debugPrint('<-- Status: ${response.statusCode} | Body: ${response.body}');
      debugPrint('===================================================');

      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        _showSuccessSnackBar(data['messageAr'] ?? 'تم إلغاء الرحلة بنجاح');
        _fetchTrips();
        return;
      } else {
        _showWarningSnackBar(data['messageAr'] ?? 'فشل إلغاء الرحلة على الخادم.');
        return;
      }
    } catch (e) {
      debugPrint('Error cancelling trip: $e');
      _showWarningSnackBar('حدث خطأ أثناء إلغاء الرحلة. يرجى التحقق من الاتصال.');
    } finally {
      setState(() {
        _isActionInProgress = false;
      });
    }
  }

  Future<void> _viewTripRoute(dynamic trip) async {
    final tripId = trip['id'] ?? trip['tripId'];
    
    setState(() {
      _isActionInProgress = true;
    });

    try {
      final token = await AuthStorage.getToken();
      if (token == null) return;

      final url = '${AppConfig.baseUrl}/Trips/$tripId/Locations';

      debugPrint('================= [HTTP REQUEST] =================');
      debugPrint('--> GET: $url');
      debugPrint('==================================================');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('================= [HTTP RESPONSE] =================');
      debugPrint('<-- Status: ${response.statusCode} | Body: ${response.body}');
      debugPrint('===================================================');

      setState(() {
        _isActionInProgress = false;
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          final List<dynamic> rawLocations = data['locations'] ?? [];
          if (rawLocations.isEmpty) {
            _showWarningSnackBar('لا توجد نقاط مسجلة لهذه الرحلة.');
            return;
          }

          final List<LatLng> path = rawLocations.map((loc) {
            final lat = double.tryParse(loc['latitude'].toString()) ?? 0.0;
            final lng = double.tryParse(loc['longitude'].toString()) ?? 0.0;
            return LatLng(lat, lng);
          }).where((latLng) => latLng.latitude != 0.0).toList();

          if (path.isEmpty) {
            _showWarningSnackBar('بيانات مسار الإحداثيات غير صالحة.');
            return;
          }

          // Open trip map screen
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TripMapScreen(
                  title: trip['description'] ?? 'مسار الرحلة الميدانية',
                  routePoints: path,
                ),
              ),
            );
          }
          return;
        }
      }
      _showWarningSnackBar('فشل جلب مسار الرحلة من الخادم.');
    } catch (e) {
      debugPrint('Error fetching trip route: $e');
      _showWarningSnackBar('حدث خطأ أثناء تحميل مسار الرحلة.');
      setState(() {
        _isActionInProgress = false;
      });
    }
  }

  void _showWarningSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.warning,
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'NEW':
        return const Color(0xFF9E9E9E); // Gray
      case 'STARTED':
        return const Color(0xFF2196F3); // Blue
      case 'COMPLETED':
        return const Color(0xFF4CAF50); // Green
      case 'CANCELLED':
        return const Color(0xFFF44336); // Red
      default:
        return Colors.black;
    }
  }

  String _getStatusArabic(String status) {
    switch (status) {
      case 'NEW':
        return 'جديدة';
      case 'STARTED':
        return 'جارية';
      case 'COMPLETED':
        return 'مكتملة';
      case 'CANCELLED':
        return 'ملغية';
      default:
        return 'غير معروف';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('رحلاتي'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'تحديث',
              onPressed: _isLoading ? null : _fetchTrips,
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Date Filter Bar
                  Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.date_range_rounded, color: AppColors.primary, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'تاريخ الرحلات المعروضة',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null && picked != _selectedDate) {
                              setState(() {
                                _selectedDate = picked;
                              });
                              _fetchTrips();
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              _formatDateForDisplay(_selectedDate),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1, thickness: 1, color: AppColors.border),

                  // Horizontal Status Tabs Filter
                  Container(
                    height: 52,
                    color: AppColors.surface,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      children: [
                        _buildTabChip('ALL', 'الكل'),
                        _buildTabChip('NEW', 'جديدة'),
                        _buildTabChip('STARTED', 'جارية'),
                        _buildTabChip('COMPLETED', 'مكتملة'),
                        _buildTabChip('CANCELLED', 'ملغية'),
                      ],
                    ),
                  ),

                  const Divider(height: 1, thickness: 1, color: AppColors.border),

                  // Main Trips List Content
                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(color: AppColors.primary),
                          )
                        : _errorMessage.isNotEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.warning),
                                      const SizedBox(height: 12),
                                      Text(
                                        _errorMessage,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontFamily: 'Cairo'),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton(
                                        onPressed: _fetchTrips,
                                        child: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Cairo')),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : _filteredTrips.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey.shade300),
                                        const SizedBox(height: 12),
                                        Text(
                                          'لا توجد رحلات في هذا التبويب للتواريخ المحددة.',
                                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontFamily: 'Cairo'),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: _filteredTrips.length,
                                    itemBuilder: (context, index) {
                                      final trip = _filteredTrips[index];
                                      return _buildTripCard(trip);
                                    },
                                  ),
                  ),
                ],
              ),
              if (_isActionInProgress)
                Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabChip(String tabKey, String label) {
    final isSelected = _activeTab == tabKey;
    final count = _getCountForTab(tabKey);
    final color = isSelected ? AppColors.primary : AppColors.textSecondary;

    return GestureDetector(
      onTap: () {
        setState(() {
          _activeTab = tabKey;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '$label ($count)',
          style: TextStyle(
            color: color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  Widget _buildTripCard(dynamic trip) {
    final status = trip['status'] ?? 'NEW';
    final statusColor = _getStatusColor(status);
    final site = trip['site'] ?? {};
    final siteName = site['nameAr'] ?? trip['siteNameAr'] ?? trip['siteName'] ?? 'بدون موقع عمل معتمد';
    final distance = trip['totalDistance'] != null ? _formatDistance(trip['totalDistance']) : null;
    final tripCode = trip['code'] ?? 'TRIP-${(trip['id'] ?? trip['tripId'] ?? 0).toString().padLeft(6, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: statusColor.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Ticket Portion
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Row (Trip Code & Status Badge)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.airplane_ticket_rounded, size: 18, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          tripCode,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _getStatusArabic(status),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Trip Description
                Text(
                  trip['description'] ?? 'زيارة ميدانية طارئة',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontFamily: 'Cairo',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),

                // Flight Route Style: Origin to Destination
                Row(
                  children: [
                    // Origin
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'نقطة الانطلاق',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: AppColors.textSecondary,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            status == 'NEW' ? 'موقعي الحالي' : 'موقع البدء الفعلي',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    
                    // Route line and icon
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 16, height: 1.2, color: Colors.grey.shade300),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.directions_car_rounded,
                            color: statusColor,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Container(width: 16, height: 1.2, color: Colors.grey.shade300),
                        ],
                      ),
                    ),

                    // Destination
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'الوجهة المستهدفة',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: AppColors.textSecondary,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            siteName,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Middle Notch Separator
          Row(
            children: [
              Transform.translate(
                offset: const Offset(-1.5, 0),
                child: Container(
                  width: 12,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                    border: Border.all(color: statusColor.withValues(alpha: 0.25), width: 1.5),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: DashedLine(color: statusColor.withValues(alpha: 0.3)),
                ),
              ),
              Transform.translate(
                offset: const Offset(1.5, 0),
                child: Container(
                  width: 12,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                    ),
                    border: Border.all(color: statusColor.withValues(alpha: 0.25), width: 1.5),
                  ),
                ),
              ),
            ],
          ),

          // 3. Bottom Ticket Stub Portion
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Boarding Details Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Text('التاريخ', style: TextStyle(fontSize: 9.5, color: AppColors.textSecondary, fontFamily: 'Cairo')),
                          const SizedBox(height: 2),
                          Text(
                            trip['tripDate'] ?? '',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 22, color: Colors.grey.shade200),
                    Expanded(
                      child: Column(
                        children: [
                          const Text('الفترة الزمنية', style: TextStyle(fontSize: 9.5, color: AppColors.textSecondary, fontFamily: 'Cairo')),
                          const SizedBox(height: 2),
                          Text(
                            '${_formatTimeForDisplay(trip['startTime'])} - ${_formatTimeForDisplay(trip['endTime'])}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                    if (distance != null) ...[
                      Container(width: 1, height: 22, color: Colors.grey.shade200),
                      Expanded(
                        child: Column(
                          children: [
                            const Text('المسافة', style: TextStyle(fontSize: 9.5, color: AppColors.textSecondary, fontFamily: 'Cairo')),
                            const SizedBox(height: 2),
                            Text(
                              distance,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                
                if (status == 'CANCELLED' && trip['cancelledReason'] != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'سبب الإلغاء: ${trip['cancelledReason']}',
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Actions block
                if (status == 'NEW' || status == 'STARTED' || status == 'COMPLETED') ...[
                  const SizedBox(height: 16),
                  _buildCardActions(trip, status),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardActions(dynamic trip, String status) {
    if (status == 'NEW') {
      return ElevatedButton.icon(
        onPressed: () => _startTrip(trip),
        icon: const Icon(Icons.play_arrow_rounded, size: 20),
        label: const Text('بدء الرحلة الميدانية', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF16A34A), // Vibrant Green
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(42),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else if (status == 'STARTED') {
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () => _endTrip(trip),
              icon: const Icon(Icons.stop_rounded, size: 20),
              label: const Text('إنهاء الرحلة', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: OutlinedButton(
              onPressed: () => _cancelTrip(trip),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                side: BorderSide(color: Colors.grey.shade400),
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('إلغاء', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            ),
          ),
        ],
      );
    } else if (status == 'COMPLETED') {
      return OutlinedButton.icon(
        onPressed: () => _viewTripRoute(trip),
        icon: const Icon(Icons.map_rounded, size: 18),
        label: const Text('عرض تفاصيل المسار والتقرير', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size.fromHeight(42),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Screen displaying the historical trip coordinates on a Google Map.
class TripMapScreen extends StatefulWidget {
  const TripMapScreen({
    super.key,
    required this.title,
    required this.routePoints,
  });

  final String title;
  final List<LatLng> routePoints;

  @override
  State<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends State<TripMapScreen> {
  GoogleMapController? _mapController;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startPoint = widget.routePoints.first;
    final endPoint = widget.routePoints.last;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          centerTitle: true,
        ),
        body: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: startPoint,
            zoom: 14,
          ),
          myLocationEnabled: false,
          zoomControlsEnabled: true,
          polylines: {
            Polyline(
              polylineId: const PolylineId('trip_path'),
              points: widget.routePoints,
              color: AppColors.primary,
              width: 5,
              geodesic: true,
            ),
          },
          markers: {
            Marker(
              markerId: const MarkerId('start'),
              position: startPoint,
              infoWindow: const InfoWindow(title: 'بداية الرحلة'),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            ),
            Marker(
              markerId: const MarkerId('end'),
              position: endPoint,
              infoWindow: const InfoWindow(title: 'نهاية الرحلة'),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            ),
          },
          onMapCreated: (controller) {
            _mapController = controller;
            
            // Adjust camera to fit the path coordinates
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fitBounds();
            });
          },
        ),
      ),
    );
  }

  Future<void> _fitBounds() async {
    if (_mapController == null) return;

    double? minLat, maxLat, minLng, maxLng;
    for (final point in widget.routePoints) {
      if (minLat == null || point.latitude < minLat) minLat = point.latitude;
      if (maxLat == null || point.latitude > maxLat) maxLat = point.latitude;
      if (minLng == null || point.longitude < minLng) minLng = point.longitude;
      if (maxLng == null || point.longitude > maxLng) maxLng = point.longitude;
    }

    if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
    }
  }
}

/// Custom clipper to shape the trip cards as flight tickets
class TicketClipper extends CustomClipper<Path> {
  const TicketClipper({required this.clipFraction});

  final double clipFraction;

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, 0);
    path.lineTo(size.width, 0);

    final cutY = size.height * clipFraction;
    const cutRadius = 10.0;

    // Right cut
    path.lineTo(size.width, cutY - cutRadius);
    path.arcToPoint(
      Offset(size.width, cutY + cutRadius),
      radius: const Radius.circular(cutRadius),
      clockwise: false,
    );
    path.lineTo(size.width, size.height);

    // Bottom
    path.lineTo(0, size.height);

    // Left cut
    path.lineTo(0, cutY + cutRadius);
    path.arcToPoint(
      Offset(0, cutY - cutRadius),
      radius: const Radius.circular(cutRadius),
      clockwise: false,
    );
    path.lineTo(0, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

/// Dashed separator line for flight ticket styles
class DashedLine extends StatelessWidget {
  const DashedLine({super.key, this.color = Colors.grey});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 5.0;
        const dashSpace = 4.0;
        final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: 1.5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
