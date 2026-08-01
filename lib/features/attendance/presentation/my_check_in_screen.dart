import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_dimensions.dart';
import '../../../app/app_config.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/utils/attendance_logger.dart';
import '../../../core/utils/device_security_helper.dart';

/// Employee Check-In/Check-Out Screen (تحضيري).
/// Features real-time GPS tracking, Google Maps, mock geofencing,
/// network time integrity checking to prevent local time tampering,
/// and SharedPreferences persistence.
class MyCheckInScreen extends StatefulWidget {
  const MyCheckInScreen({super.key});

  @override
  State<MyCheckInScreen> createState() => _MyCheckInScreenState();
}

class _MyCheckInScreenState extends State<MyCheckInScreen> {
  // Geofence center (Default Cairo Headquarters coordinates)
  static const double _targetLat = 30.0444;
  static const double _targetLng = 31.2357;

  static const _securityPlatform = MethodChannel('com.example.locksys_hr/device_security');

  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _isLoadingLocation = true;
  bool _isVerifyingTime = false;
  bool _timeTampered = false;
  bool _gpsDisabled = false;
  bool _gpsPermissionDenied = false;
  bool _connectionError = false;
  bool _isSubmitting = false;

  // Spoofed coordinate detection
  bool _isFake = false;
  bool _isDevMode = false;

  // Site selection state variables
  List<dynamic> _sites = [];
  Map<String, dynamic>? _selectedSite;

  // Site locations / zones state variables
  List<dynamic> _locations = [];
  Map<String, dynamic>? _selectedLocation;
  bool _isLoadingLocations = false;
  bool _isLocationRequired = true;

  // API attendance status checking variables
  String _apiAttendanceStatus = 'NOT_PRESENT';
  String? _apiCheckInTime;
  String? _apiCheckOutTime;
  double? _apiWorkingHours;
  bool _isLoadingStatus = false;

  Future<bool> _checkDeveloperOptions() async {
    if (Platform.isAndroid) {
      try {
        final bool isDevMode = await _securityPlatform.invokeMethod('isDeveloperOptionsEnabled');
        return isDevMode;
      } on PlatformException catch (_) {
        return false;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    unawaited(AttendanceLogger.logScreenActivity('CHECK_IN'));
    _initializeData();
  }

  Future<void> _initializeData() async {
    // 1. Start fetching GPS in background immediately
    unawaited(_determinePosition());

    // 2. Load checkLocation preference and cached site from local storage to display instantly
    try {
      final locationReq = await AuthStorage.isLocationRequired();
      if (mounted) {
        setState(() {
          _isLocationRequired = locationReq;
        });
      }

      final userData = await AuthStorage.getUserData();
      if (userData != null && userData['employee'] != null) {
        final employee = userData['employee'];
        final site = employee['site'];
        if (site != null && site is Map<String, dynamic>) {
          if (mounted) {
            setState(() {
              _selectedSite = site;
            });
            // Fetch locations for this site immediately from server
            unawaited(_fetchSiteLocations(site['siteId']));
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading cached site/preferences: $e');
    }

    // 3. Fetch sites list and status from server in parallel
    unawaited(_fetchSites());
    await _checkEmployeeStatus();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _checkEmployeeStatus() async {
    if (mounted) {
      setState(() {
        _isLoadingStatus = true;
      });
    }

    try {
      final token = await AuthStorage.getToken();
      final empId = await AuthStorage.getEmployeeId();
      final userData = await AuthStorage.getUserData();

      debugPrint('================= [DEBUG STATUS CHECK] =================');
      debugPrint('Token: $token');
      debugPrint('Employee ID: $empId');
      debugPrint('User Data: $userData');
      debugPrint('========================================================');

      if (token == null || empId == null) {
        if (mounted) {
          setState(() {
            _isLoadingStatus = false;
          });
        }
        return;
      }

      final date = DateTime.now();
      final dateFilter = '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
      
      final url = '${AppConfig.baseUrl}/MyEmployees/CheckEmployeeStatus?employee_id=$empId&date_filter=$dateFilter';

      unawaited(AttendanceLogger.logHttpRequest(
        url: url,
        method: 'GET',
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ));

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      unawaited(AttendanceLogger.logHttpResponse(
        url: url,
        statusCode: response.statusCode,
        body: response.body,
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['attendance'] != null) {
          final att = data['attendance'];
          final status = att['attendanceStatus']?.toString().toUpperCase() ?? 'NOT_PRESENT';
          final checkInStr = att['checkInTime']?.toString();
          final checkOutStr = att['checkOutTime']?.toString();
          final workingHrs = att['workingHours'] != null ? double.tryParse(att['workingHours'].toString()) : null;
          if (mounted) {
            setState(() {
              _apiAttendanceStatus = status;
              _apiCheckInTime = (checkInStr != null && checkInStr.toLowerCase() != 'null') ? checkInStr : null;
              _apiCheckOutTime = (checkOutStr != null && checkOutStr.toLowerCase() != 'null') ? checkOutStr : null;
              _apiWorkingHours = workingHrs;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking employee status: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingStatus = false;
        });
      }
    }
  }

  /// Verifies if local phone time matches network/server time to prevent tampering.
  /// Returns the verified server time if successful and match is within bounds.
  Future<DateTime?> _verifyTimeIntegrity() async {
    setState(() {
      _isVerifyingTime = true;
      _connectionError = false;
    });

    try {
      // Request server time by making a quick HEAD request to the API
      final response = await http
          .head(Uri.parse(AppConfig.baseUrl))
          .timeout(const Duration(seconds: 5));

      final dateHeader = response.headers['date'];
      if (dateHeader != null) {
        final serverTime = HttpDate.parse(dateHeader).toLocal();
        final localTime = DateTime.now();

        // Check difference in minutes
        final diff = localTime.difference(serverTime).abs().inMinutes;
        if (diff > 5) {
          if (mounted) {
            setState(() {
              _timeTampered = true;
              _isVerifyingTime = false;
            });
          }
          return null;
        }

        if (mounted) {
          setState(() {
            _timeTampered = false;
            _isVerifyingTime = false;
          });
        }
        return serverTime;
      }
    } catch (e) {
      debugPrint('Time integrity check failed (offline or server error): $e');
      if (mounted) {
        setState(() {
          _connectionError = true;
          _isVerifyingTime = false;
        });
      }
      return null;
    }

    if (mounted) {
      setState(() {
        _isVerifyingTime = false;
      });
    }
    return null;
  }

  /// Requests permissions and retrieves current GPS coordinates.
  Future<void> _determinePosition() async {
    if (mounted) {
      setState(() {
        _isLoadingLocation = true;
        _gpsDisabled = false;
        _gpsPermissionDenied = false;
        _isDevMode = false;
      });
    }

    try {
      // 1. Check Developer Options (Android only)
      final bool isDevModeEnabled = await _checkDeveloperOptions();
      if (isDevModeEnabled) {
        if (mounted) {
          setState(() {
            _isDevMode = true;
            _isLoadingLocation = false;
          });
        }
        return;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _gpsDisabled = true;
            _isLoadingLocation = false;
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _gpsPermissionDenied = true;
              _isLoadingLocation = false;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _gpsPermissionDenied = true;
            _isLoadingLocation = false;
          });
        }
        return;
      }

      // Try last known position for instant map loading
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        _updateLocationAndDistance(lastKnown);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).timeout(const Duration(seconds: 5));

      _updateLocationAndDistance(position);
    } catch (e) {
      debugPrint('Error getting GPS coordinates: $e');
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  void _updateLocationAndDistance(Position position) {
    if (!mounted) return;

    bool isMockedGps = false;
    try {
      isMockedGps = position.isMocked;
    } catch (_) {}

    setState(() {
      _currentPosition = position;
      _isFake = isMockedGps;
      _isLoadingLocation = false;
    });

    // Animate map controller to focus on active location
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(position.latitude, position.longitude),
        15,
      ),
    );
  }



  Future<void> _openExternalMap(LatLng coords) async {
    final url = Uri.parse("https://www.google.com/maps/search/?api=1&query=${coords.latitude},${coords.longitude}");
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        _showWarningSnackBar('تعذر فتح تطبيق الخرائط الخارجي');
      }
    } catch (e) {
      _showWarningSnackBar('حدث خطأ أثناء محاولة فتح الخريطة: $e');
    }
  }

  Future<void> _fetchSites() async {
    try {
      final token = await AuthStorage.getToken();
      if (token == null) return;

      final url = '${AppConfig.baseUrl}/Users/MySites';

      debugPrint('================= [HTTP REQUEST] =================');
      debugPrint('--> GET: $url');
      debugPrint('Headers: {Authorization: Bearer $token, Accept: application/json}');
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
          final List<dynamic> fetchedSites = data['sites'] ?? [];
          if (mounted) {
            setState(() {
              _sites = fetchedSites;
              if (fetchedSites.isNotEmpty) {
                final primary = fetchedSites.firstWhere(
                  (s) => s['isPrimary'] == true || s['isPrimary'] == 1,
                  orElse: () => fetchedSites.first,
                );
                _selectedSite = primary;
              }
            });
            if (_selectedSite != null) {
              _fetchSiteLocations(_selectedSite!['siteId']);
            }
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error fetching sites: $e');
    }
  }

  Future<void> _fetchSiteLocations(int siteId) async {
    if (mounted) {
      setState(() {
        _isLoadingLocations = true;
        _locations = [];
        _selectedLocation = null;
      });
    }

    try {
      final token = await AuthStorage.getToken();
      if (token == null) return;

      final url = '${AppConfig.baseUrl}/Users/SiteLocations?site_id=$siteId';

      debugPrint('================= [HTTP REQUEST] =================');
      debugPrint('--> GET: $url');
      debugPrint('Headers: {Authorization: Bearer $token, Accept: application/json}');
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
          final rawLocs = data['locations'] ?? data['location'];
          List<dynamic> fetchedLocs = [];
          if (rawLocs != null) {
            if (rawLocs is List) {
              fetchedLocs = rawLocs;
            } else if (rawLocs is Map) {
              fetchedLocs = [rawLocs];
            }
          }

          if (mounted) {
            setState(() {
              _locations = fetchedLocs;
              if (fetchedLocs.isNotEmpty) {
                _selectedLocation = fetchedLocs.first;
              }
            });
            // Animate map camera to show center of default zone if available
            if (_selectedLocation != null) {
              final centerLat = double.tryParse(_selectedLocation!['latitude']?.toString() ?? '') ?? 0.0;
              final centerLng = double.tryParse(_selectedLocation!['longitude']?.toString() ?? '') ?? 0.0;
              if (centerLat != 0.0 && centerLng != 0.0) {
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(centerLat, centerLng),
                    16,
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching site locations: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocations = false;
        });
      }
    }
  }

  void _onLocationChanged(Map<String, dynamic>? loc) {
    if (loc == null) return;
    setState(() {
      _selectedLocation = loc;
    });

    final centerLat = double.tryParse(loc['latitude']?.toString() ?? '') ?? 0.0;
    final centerLng = double.tryParse(loc['longitude']?.toString() ?? '') ?? 0.0;
    if (centerLat != 0.0 && centerLng != 0.0) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(centerLat, centerLng),
          16,
        ),
      );
    }
  }

  bool _isUserInZone(Position userPos, Map<String, dynamic> zone) {
    final zoneType = zone['zoneType']?.toString().toUpperCase() ?? 'CIRCLE';
    final centerLat = double.tryParse(zone['latitude']?.toString() ?? '') ?? 0.0;
    final centerLng = double.tryParse(zone['longitude']?.toString() ?? '') ?? 0.0;

    bool inCircle = false;
    if (zoneType == 'CIRCLE' || zoneType == 'BOTH') {
      final radius = double.tryParse(zone['zoneRadius']?.toString() ?? '') ?? 0.0;
      if (radius > 0 && centerLat != 0.0 && centerLng != 0.0) {
        final distance = Geolocator.distanceBetween(
          userPos.latitude,
          userPos.longitude,
          centerLat,
          centerLng,
        );
        if (distance <= radius) {
          inCircle = true;
        }
      }
    }

    bool inRect = false;
    if (zoneType == 'RECT' || zoneType == 'BOTH') {
      final bounds = zone['zoneBounds'] as Map<String, dynamic>?;
      if (bounds != null) {
        final latNorth = double.tryParse(bounds['latNorth']?.toString() ?? '');
        final lngEast = double.tryParse(bounds['lngEast']?.toString() ?? '');
        final latSouth = double.tryParse(bounds['latSouth']?.toString() ?? '');
        final lngWest = double.tryParse(bounds['lngWest']?.toString() ?? '');

        if (latNorth != null && lngEast != null && latSouth != null && lngWest != null) {
          if (userPos.latitude >= latSouth &&
              userPos.latitude <= latNorth &&
              userPos.longitude >= lngWest &&
              userPos.longitude <= lngEast) {
            inRect = true;
          }
        }
      }
    }

    if (zoneType == 'CIRCLE') return inCircle;
    if (zoneType == 'RECT') return inRect;
    if (zoneType == 'BOTH') return inCircle || inRect;
    return false;
  }

  Set<Circle> _buildCircles() {
    final Set<Circle> circles = {};
    if (_locations.isEmpty && _selectedLocation != null) {
      _addCircleForLocation(_selectedLocation!, circles);
    } else {
      for (final loc in _locations) {
        if (loc is Map<String, dynamic>) {
          _addCircleForLocation(loc, circles);
        }
      }
    }
    return circles;
  }

  void _addCircleForLocation(Map<String, dynamic> loc, Set<Circle> circles) {
    final zoneType = loc['zoneType']?.toString().toUpperCase() ?? 'CIRCLE';
    if (zoneType == 'CIRCLE' || zoneType == 'BOTH') {
      final centerLat = double.tryParse(loc['latitude']?.toString() ?? '') ?? 0.0;
      final centerLng = double.tryParse(loc['longitude']?.toString() ?? '') ?? 0.0;
      final radius = double.tryParse(loc['zoneRadius']?.toString() ?? '') ?? 0.0;
      final id = loc['id']?.toString() ?? 'default';

      if (centerLat != 0.0 && centerLng != 0.0 && radius > 0) {
        final isSelected = _selectedLocation != null && _selectedLocation!['id'] == loc['id'];
        circles.add(
          Circle(
            circleId: CircleId('zone_circle_$id'),
            center: LatLng(centerLat, centerLng),
            radius: radius,
            fillColor: (isSelected ? AppColors.primary : Colors.grey).withValues(alpha: 0.15),
            strokeColor: isSelected ? AppColors.primary : Colors.grey,
            strokeWidth: 2,
          ),
        );
      }
    }
  }

  Set<Polygon> _buildPolygons() {
    final Set<Polygon> polygons = {};
    if (_locations.isEmpty && _selectedLocation != null) {
      _addPolygonForLocation(_selectedLocation!, polygons);
    } else {
      for (final loc in _locations) {
        if (loc is Map<String, dynamic>) {
          _addPolygonForLocation(loc, polygons);
        }
      }
    }
    return polygons;
  }

  void _addPolygonForLocation(Map<String, dynamic> loc, Set<Polygon> polygons) {
    final zoneType = loc['zoneType']?.toString().toUpperCase() ?? 'CIRCLE';
    if (zoneType == 'RECT' || zoneType == 'BOTH') {
      final bounds = loc['zoneBounds'] as Map<String, dynamic>?;
      if (bounds != null) {
        final latNorth = double.tryParse(bounds['latNorth']?.toString() ?? '');
        final lngEast = double.tryParse(bounds['lngEast']?.toString() ?? '');
        final latSouth = double.tryParse(bounds['latSouth']?.toString() ?? '');
        final lngWest = double.tryParse(bounds['lngWest']?.toString() ?? '');
        final id = loc['id']?.toString() ?? 'default';

        if (latNorth != null && lngEast != null && latSouth != null && lngWest != null) {
          final isSelected = _selectedLocation != null && _selectedLocation!['id'] == loc['id'];
          polygons.add(
            Polygon(
              polygonId: PolygonId('zone_rect_$id'),
              points: [
                LatLng(latNorth, lngWest),
                LatLng(latNorth, lngEast),
                LatLng(latSouth, lngEast),
                LatLng(latSouth, lngWest),
              ],
              fillColor: (isSelected ? Colors.blue : Colors.grey).withValues(alpha: 0.15),
              strokeColor: isSelected ? Colors.blue : Colors.grey,
              strokeWidth: 2,
            ),
          );
        }
      }
    }
  }

  Set<Marker> _buildMarkers(double activeLat, double activeLng) {
    final markers = {
      Marker(
        markerId: const MarkerId('current_pos'),
        position: LatLng(activeLat, activeLng),
        infoWindow: InfoWindow(
          title: _isFake ? 'الموقع الوهمي (Spoofed)' : 'موقعك الحالي',
          snippet: '${activeLat.toStringAsFixed(6)}, ${activeLng.toStringAsFixed(6)}',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          _isFake ? BitmapDescriptor.hueRed : BitmapDescriptor.hueGreen,
        ),
      ),
    };

    if (_locations.isEmpty && _selectedLocation != null) {
      _addMarkerForLocation(_selectedLocation!, markers);
    } else {
      for (final loc in _locations) {
        if (loc is Map<String, dynamic>) {
          _addMarkerForLocation(loc, markers);
        }
      }
    }
    return markers;
  }

  void _addMarkerForLocation(Map<String, dynamic> loc, Set<Marker> markers) {
    final centerLat = double.tryParse(loc['latitude']?.toString() ?? '') ?? 0.0;
    final centerLng = double.tryParse(loc['longitude']?.toString() ?? '') ?? 0.0;
    final id = loc['id']?.toString() ?? 'default';

    if (centerLat != 0.0 && centerLng != 0.0) {
      final isSelected = _selectedLocation != null && _selectedLocation!['id'] == loc['id'];
      markers.add(
        Marker(
          markerId: MarkerId('zone_center_$id'),
          position: LatLng(centerLat, centerLng),
          infoWindow: InfoWindow(
            title: loc['nameAr'] ?? loc['nameEn'] ?? 'مركز المنطقة',
            snippet: loc['notes'] ?? '',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isSelected ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueYellow,
          ),
        ),
      );
    }
  }

  void _showSiteSelectionBottomSheet() {
    if (_sites.isEmpty) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اختر موقع العمل للتحضير',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _sites.length,
                    itemBuilder: (context, index) {
                      final site = _sites[index];
                      final isSelected = _selectedSite?['siteId'] == site['siteId'];
                      return ListTile(
                        title: Text(
                          site['nameAr'] ?? '',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                            : null,
                        selected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedSite = site;
                          });
                          _fetchSiteLocations(site['siteId']);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatServerDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatServerTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _submitAttendance({
    required String checkType,
    required DateTime serverTime,
  }) async {
    setState(() {
      _isSubmitting = true;
    });

    LatLng realCoords = LatLng(
      _currentPosition?.latitude ?? _targetLat,
      _currentPosition?.longitude ?? _targetLng,
    );
    LatLng? fakeCoords;
    int isFake = 0;

    if (_isFake) {
      isFake = 1;
      fakeCoords = LatLng(
        _currentPosition?.latitude ?? _targetLat,
        _currentPosition?.longitude ?? _targetLng,
      );
    }

    final targetDate = serverTime;

    try {
      final token = await AuthStorage.getToken();
      if (token == null) {
        _showWarningDialog(
          title: 'جلسة منتهية',
          content: 'انتهت جلستك الحالية. يرجى تسجيل الخروج والولوج مجدداً.',
        );
        return;
      }

      final deviceUuid = await DeviceSecurityHelper.getDeviceUuid();

      final bodyData = {
        "checkType": checkType,
        "attendanceDate": _formatServerDate(targetDate),
        "actualTime": _formatServerTime(serverTime),
        "latitude": realCoords.latitude.toString(),
        "longitude": realCoords.longitude.toString(),
        "isFake": isFake,
        "fakeLatitude": fakeCoords?.latitude.toString(),
        "fakeLongitude": fakeCoords?.longitude.toString(),
        "notes": "",
        "deviceUuid": deviceUuid,
        if (_selectedSite != null) ...{
          "sitesId": _selectedSite!['siteId'],
          "siteId": _selectedSite!['siteId'],
        },
        if (_selectedLocation != null) ...{
          "locationId": _selectedLocation!['id'],
        }
      };

      final url = '${AppConfig.baseUrl}/Users/CheckInAndOut';
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final bodyString = jsonEncode(bodyData);

      debugPrint('================= [HTTP REQUEST] =================');
      debugPrint('--> POST: $url');
      debugPrint('Headers: $headers');
      debugPrint('Body: $bodyString');
      debugPrint('==================================================');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: bodyString,
      );

      debugPrint('================= [HTTP RESPONSE] =================');
      debugPrint('<-- Status: ${response.statusCode} | URL: $url');
      debugPrint('Response Body: ${response.body}');
      debugPrint('===================================================');

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final attendance = responseData['attendance'];
        final isOutOfRange = attendance != null && (attendance['isOutOfRange'] == true);

        await _checkEmployeeStatus();

        final baseMsg = responseData['messageAr'] ?? 'تم تسجيل العملية بنجاح';
        final rangeMsg = isOutOfRange ? ' (خارج النطاق)' : ' (داخل النطاق)';
        _showSuccessSnackBar('$baseMsg$rangeMsg');
      } else {
        _showWarningDialog(
          title: 'فشل العملية',
          content:
              responseData['messageAr'] ??
              'حدث خطأ أثناء الاتصال بالخادم. يرجى المحاولة لاحقاً.',
        );
      }
    } catch (e) {
      debugPrint('================= [HTTP EXCEPTION] =================');
      debugPrint(
        'xxx Error: $e | URL: ${AppConfig.baseUrl}/Users/CheckInAndOut',
      );
      debugPrint('====================================================');
      debugPrint('Error submitting attendance: $e');
      _showWarningDialog(
        title: 'خطأ في الاتصال',
        content:
            'حدث خطأ في الاتصال بالشبكة. يرجى التحقق من اتصالك بالإنترنت والمحاولة مجدداً.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  /// Handles check-in submission.
  Future<void> _handleCheckIn() async {
    // 1. Mock location check
    if (_isFake) {
      _showWarningDialog(
        title: 'تنبيه الموقع الوهمي',
        content: 'لقد تم كشف تشغيل موقع وهمي (Mock Location) على هاتفك. لا يمكنك تسجيل الحضور أو الانصراف إلا بعد إغلاق برنامج الموقع الوهمي وتفعيل الموقع الحقيقي.',
      );
      return;
    }

    // 2. Check GPS availability
    if (_currentPosition == null) {
      _showWarningSnackBar('يرجى تمكين تحديد الموقع الجغرافي (GPS) أولاً');
      return;
    }

    // 3. Check selected zone
    if (_isLocationRequired && _selectedLocation == null) {
      _showWarningDialog(
        title: 'تحديد المنطقة مطلوب',
        content: 'يرجى اختيار منطقة التحضير (الزون) أولاً للتحقق من موقعك.',
      );
      return;
    }

    // 4. Verify user is in the selected zone
    if (_isLocationRequired && !_isUserInZone(_currentPosition!, _selectedLocation!)) {
      _showWarningDialog(
        title: 'خارج النطاق الجغرافي',
        content: 'أنت خارج النطاق الجغرافي للمنطقة المحددة (${_selectedLocation!['nameAr'] ?? _selectedLocation!['nameEn']}). يرجى الاقتراب من المنطقة لتتمكن من تسجيل الحضور.',
      );
      return;
    }

    // 5. Verify Time Integrity (Anti-tampering mechanism)
    final serverTime = await _verifyTimeIntegrity();
    if (serverTime == null) {
      if (_connectionError) {
        _showWarningDialog(
          title: 'خطأ في الاتصال',
          content:
              'تعذر الاتصال بالخادم للتحقق من التوقيت. يرجى التأكد من اتصالك بالإنترنت والمحاولة مجدداً.',
        );
      } else {
        _showWarningDialog(
          title: 'خطأ في توقيت الهاتف',
          content:
              'توقيت وتاريخ هاتفك الحالي غير صحيحين أو تم تعديلهما يدوياً. يرجى تفعيل خيار "الضبط التلقائي للتاريخ والوقت" في إعدادات جهازك للتسجيل.',
        );
      }
      return;
    }

    // 6. Submit to server
    await _submitAttendance(checkType: 'IN', serverTime: serverTime);
  }

  /// Handles check-out submission.
  Future<void> _handleCheckOut() async {
    // 1. Mock location check
    if (_isFake) {
      _showWarningDialog(
        title: 'تنبيه الموقع الوهمي',
        content: 'لقد تم كشف تشغيل موقع وهمي (Mock Location) على هاتفك. لا يمكنك تسجيل الحضور أو الانصراف إلا بعد إغلاق برنامج الموقع الوهمي وتفعيل الموقع الحقيقي.',
      );
      return;
    }

    // 2. Check GPS availability
    if (_currentPosition == null) {
      _showWarningSnackBar('يرجى تمكين تحديد الموقع الجغرافي (GPS) أولاً');
      return;
    }

    // 3. Check selected zone
    if (_isLocationRequired && _selectedLocation == null) {
      _showWarningDialog(
        title: 'تحديد المنطقة مطلوب',
        content: 'يرجى اختيار منطقة التحضير (الزون) أولاً للتحقق من موقعك.',
      );
      return;
    }

    // 4. Verify user is in the selected zone
    if (_isLocationRequired && !_isUserInZone(_currentPosition!, _selectedLocation!)) {
      _showWarningDialog(
        title: 'خارج النطاق الجغرافي',
        content: 'أنت خارج النطاق الجغرافي للمنطقة المحددة (${_selectedLocation!['nameAr'] ?? _selectedLocation!['nameEn']}). يرجى الاقتراب من المنطقة لتتمكن من تسجيل الانصراف.',
      );
      return;
    }

    // 5. Verify Time Integrity (Anti-tampering mechanism)
    final serverTime = await _verifyTimeIntegrity();
    if (serverTime == null) {
      if (_connectionError) {
        _showWarningDialog(
          title: 'خطأ في الاتصال',
          content:
              'تعذر الاتصال بالخادم للتحقق من التوقيت. يرجى التأكد من اتصالك بالإنترنت والمحاولة مجدداً.',
        );
      } else {
        _showWarningDialog(
          title: 'خطأ في توقيت الهاتف',
          content:
              'توقيت وتاريخ هاتفك الحالي غير صحيحين أو تم تعديلهما يدوياً. يرجى تفعيل خيار "الضبط التلقائي للتاريخ والوقت" في إعدادات جهازك للتسجيل.',
        );
      }
      return;
    }

    // 6. Submit to server
    await _submitAttendance(checkType: 'OUT', serverTime: serverTime);
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

  void _showWarningDialog({required String title, required String content}) {
    showDialog(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            content: Text(
              content,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppColors.textPrimary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'حسناً',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double activeLat = _targetLat;
    double activeLng = _targetLng;

    if (_currentPosition != null) {
      activeLat = _currentPosition!.latitude;
      activeLng = _currentPosition!.longitude;
    } else if (_selectedLocation != null) {
      activeLat = double.tryParse(_selectedLocation!['latitude']?.toString() ?? '') ?? _targetLat;
      activeLng = double.tryParse(_selectedLocation!['longitude']?.toString() ?? '') ?? _targetLng;
    }

    Widget bodyContent;

    if (_isVerifyingTime || _isSubmitting || _isLoadingStatus) {
      bodyContent = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              _isVerifyingTime
                  ? 'جاري التحقق من أمان ومزامنة الوقت...'
                  : _isSubmitting
                      ? 'جاري تسجيل طلبك على الخادم...'
                      : 'جاري التحقق من حالة التحضير الحالية...',
              style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
            ),
          ],
        ),
      );
    } else if (_apiAttendanceStatus == 'COMPLETE' || _apiAttendanceStatus == 'COMPLETED') {
      bodyContent = Container(
        color: AppColors.background,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    color: AppColors.success,
                    size: 80,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'تم تسجيل حضورك وانصرافك اليوم بنجاح!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'لقد استكملت ساعات العمل المطلوبة لهذا اليوم.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo',
                  ),
                ),
                if (_apiCheckInTime != null || _apiCheckOutTime != null) ...[
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        if (_apiCheckInTime != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.login_rounded, color: AppColors.success, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'وقت الحضور',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                _apiCheckInTime!,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          if (_apiCheckOutTime != null) const Divider(height: 24),
                        ],
                        if (_apiCheckOutTime != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.logout_rounded, color: Color(0xFFD97706), size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'وقت الانصراف',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                _apiCheckOutTime!,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_apiWorkingHours != null) ...[
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.work_history_rounded, color: AppColors.primary, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'ساعات العمل',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '${_apiWorkingHours!.toStringAsFixed(2)} ساعة',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    } else if (_isDevMode) {
      bodyContent = _buildSecurityBlockView(
        icon: Icons.developer_mode_rounded,
        title: 'خيارات المطور مفعلة',
        message: 'تم كشف تفعيل "خيارات مطور البرامج" (Developer Options) على جهازك. لدواعي أمان العمل والتحضير، يرجى إيقاف تفعيل خيارات المطور من إعدادات الهاتف للاستمرار.',
        buttonText: 'إعادة التحقق',
        onButtonPressed: _determinePosition,
      );
    } else if (_gpsDisabled) {
      bodyContent = _buildSecurityBlockView(
        icon: Icons.location_off_rounded,
        title: 'خدمات الموقع معطلة',
        message: 'خدمة تحديد الموقع (GPS) مغلقة على هاتفك. لا يمكنك استخدام التطبيق أو تسجيل حضورك دون تفعيل خدمة الموقع الجغرافي.',
        buttonText: 'تفعيل الموقع الجغرافي',
        onButtonPressed: () async {
          await Geolocator.openLocationSettings();
          _determinePosition();
        },
        secondaryButtonText: 'تحديث الحالة',
        onSecondaryButtonPressed: _determinePosition,
      );
    } else if (_gpsPermissionDenied) {
      bodyContent = _buildSecurityBlockView(
        icon: Icons.location_disabled_rounded,
        title: 'صلاحيات الموقع مرفوضة',
        message: 'صلاحية تحديد الموقع الجغرافي مرفوضة للتطبيق. لا يمكنك استخدام التطبيق أو تسجيل حضورك دون إعطاء صلاحيات الموقع.',
        buttonText: 'منح الصلاحيات للتطبيق',
        onButtonPressed: () async {
          await Geolocator.openAppSettings();
          _determinePosition();
        },
        secondaryButtonText: 'إعادة المحاولة',
        onSecondaryButtonPressed: _determinePosition,
      );
    } else if (_isFake) {
      bodyContent = _buildSecurityBlockView(
        icon: Icons.security_rounded,
        title: 'موقع وهمي نشط',
        message: 'تم كشف استخدام تطبيق لتزييف الموقع (Mock Location) على هاتفك. يرجى إغلاق وإلغاء تفعيل أي برامج للمواقع الوهمية وتفعيل موقعك الحقيقي للاستمرار.',
        buttonText: 'تحديث الموقع والتحقق',
        onButtonPressed: _determinePosition,
      );
    } else {
      bodyContent = SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User Profile Header Info
              _EmployeeHeaderCard(
                selectedSiteName: _selectedSite?['nameAr'] ?? 'الفرع الرئيسي',
                selectedLocationName: !_isLocationRequired
                    ? 'بصمة حرة (من أي مكان)'
                    : (_selectedLocation?['nameAr'] ?? _selectedLocation?['nameEn'] ?? 'جاري تحديد المنطقة...'),
                showChangeButton: _sites.isNotEmpty,
                onChangePressed: _showSiteSelectionBottomSheet,
              ),
              if (_sites.length > 1) ...[
                const SizedBox(height: AppDimensions.spaceMd),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_city_rounded, color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'اختر موقع التحضير الحالي',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _sites.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final site = _sites[index];
                          final isSelected = _selectedSite?['siteId'] == site['siteId'];
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedSite = site;
                              });
                              _fetchSiteLocations(site['siteId']);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.05)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.border,
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          site['nameAr'] ?? '',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            color: AppColors.textPrimary,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                        if (site['isPrimary'] == true || site['isPrimary'] == 1) ...[
                                          const SizedBox(height: 2),
                                          const Text(
                                            'الموقع الأساسي المعتمد',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  // ignore: deprecated_member_use_from_same_package, deprecated_member_use
                                  Radio<int>(
                                    value: site['siteId'] as int,
                                    // ignore: deprecated_member_use_from_same_package, deprecated_member_use
                                    groupValue: _selectedSite?['siteId'] as int?,
                                    activeColor: AppColors.primary,
                                    // ignore: deprecated_member_use_from_same_package, deprecated_member_use
                                    onChanged: (_) {
                                      setState(() {
                                        _selectedSite = site;
                                      });
                                      _fetchSiteLocations(site['siteId']);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppDimensions.spaceMd),

              if (_isLoadingLocations)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (_locations.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.pin_drop_rounded, color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'اختر منطقة التحضير (الزون)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _selectedLocation?['id'] as int?,
                            isExpanded: true,
                            hint: const Text(
                              'اختر المنطقة',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                            ),
                            dropdownColor: AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            items: _locations.map((loc) {
                              return DropdownMenuItem<int>(
                                value: loc['id'] as int?,
                                child: Text(
                                  loc['nameAr'] ?? loc['nameEn'] ?? '',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                final matched = _locations.firstWhere(
                                  (l) => l['id'] == val,
                                  orElse: () => null,
                                );
                                if (matched != null) {
                                  _onLocationChanged(matched);
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLocationRequired && _selectedLocation != null && _currentPosition != null) ...[
                  const SizedBox(height: AppDimensions.spaceMd),
                  _ZoneStatusCard(
                    isInside: _isUserInZone(_currentPosition!, _selectedLocation!),
                    zoneName: _selectedLocation!['nameAr'] ?? _selectedLocation!['nameEn'] ?? '',
                  ),
                ],
                if (!_isLocationRequired) ...[
                  const SizedBox(height: AppDimensions.spaceMd),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, color: AppColors.primary, size: 24),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'بصمة حرة: مسموح لك بتسجيل التحضير من أي مكان عبر الهاتف الجغرافي.',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppDimensions.spaceMd),
              ] else if (_isLocationRequired && !_isLoadingLocations && _locations.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: AppColors.error, size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'لا توجد مناطق تحضير (زونات) مخصصة لهذا الموقع حالياً. يرجى مراجعة المسؤول.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.error,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceMd),
              ],

              // Map Widget Container
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(activeLat, activeLng),
                          zoom: 15,
                        ),
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        markers: _buildMarkers(activeLat, activeLng),
                        circles: _buildCircles(),
                        polygons: _buildPolygons(),
                        onMapCreated: (controller) {
                          _mapController = controller;
                        },
                      ),
                      if (_isLoadingLocation)
                        Container(
                          color: Colors.black.withValues(alpha: 0.15),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Column(
                          children: [
                            _MapIconButton(
                              icon: _isFake ? Icons.gps_off_rounded : Icons.my_location_rounded,
                              label: 'تحديد موقعي',
                              color: _isFake ? Colors.red : Colors.green,
                              onTap: () {
                                _mapController?.animateCamera(
                                  CameraUpdate.newLatLngZoom(
                                    LatLng(activeLat, activeLng),
                                    16,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Stats & Location integrity Panel
              _AttendanceStatsCard(
                timeTampered: _timeTampered,
                apiAttendanceStatus: _apiAttendanceStatus,
                apiCheckInTime: _apiCheckInTime,
                apiCheckOutTime: _apiCheckOutTime,
                apiWorkingHours: _apiWorkingHours,
                coords: _currentPosition != null
                    ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                    : null,
                isFake: _isFake,
                onOpenMap: _openExternalMap,
              ),
              const SizedBox(height: AppDimensions.spaceLg),

              // Conditional Check-in / Check-out button triggers
              if (_timeTampered)
                ElevatedButton(
                  onPressed: () => _verifyTimeIntegrity(),
                  child: const Text('إعادة التحقق من وقت الهاتف'),
                )
              else if (_apiAttendanceStatus == 'NOT_PRESENT')
                ElevatedButton.icon(
                  onPressed: _isLoadingLocation
                      ? null
                      : _handleCheckIn,
                  icon: const Icon(
                    Icons.fingerprint_rounded,
                    size: 26,
                  ),
                  label: const Text('تسجيل الحضور اليومي'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(56),
                  ),
                )
              else if (_apiAttendanceStatus == 'CHECKED_IN')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_apiCheckInTime != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.alarm_on_rounded, size: 18, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text(
                              'تم تسجيل حضورك الساعة $_apiCheckInTime',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    ElevatedButton.icon(
                      onPressed: _isLoadingLocation
                          ? null
                          : _handleCheckOut,
                      icon: const Icon(
                        Icons.exit_to_app_rounded,
                        size: 26,
                      ),
                      label: const Text('تسجيل الانصراف اليومي'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(
                          0xFFD97706,
                        ), // Orange
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('تحضيري'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: bodyContent,
        ),
      ),
    );
  }

  Widget _buildSecurityBlockView({
    required IconData icon,
    required String title,
    required String message,
    required String buttonText,
    required VoidCallback onButtonPressed,
    String? secondaryButtonText,
    VoidCallback? onSecondaryButtonPressed,
  }) {
    return Container(
      color: AppColors.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: AppColors.primary,
                  size: 80,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  fontFamily: 'Cairo',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.6,
                  color: AppColors.textSecondary,
                  fontFamily: 'Cairo',
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: onButtonPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(56),
                ),
                child: Text(
                  buttonText,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (secondaryButtonText != null && onSecondaryButtonPressed != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onSecondaryButtonPressed,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: Text(
                    secondaryButtonText,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeHeaderCard extends StatelessWidget {
  const _EmployeeHeaderCard({
    required this.selectedSiteName,
    required this.selectedLocationName,
    required this.showChangeButton,
    required this.onChangePressed,
  });

  final String selectedSiteName;
  final String selectedLocationName;
  final bool showChangeButton;
  final VoidCallback onChangePressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFE53935), // Vibrant Red
            Color(0xFFB71C1C), // Deep premium Red
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB71C1C).withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_on_rounded,
            color: Colors.white,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'الفرع: $selectedSiteName',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  selectedLocationName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (showChangeButton) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onChangePressed,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.swap_horiz_rounded,
                      color: Color(0xFFB71C1C),
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'تغيير',
                      style: TextStyle(
                        color: Color(0xFFB71C1C),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttendanceStatsCard extends StatelessWidget {
  const _AttendanceStatsCard({
    required this.timeTampered,
    required this.apiAttendanceStatus,
    this.apiCheckInTime,
    this.apiCheckOutTime,
    this.apiWorkingHours,
    this.coords,
    this.isFake = false,
    this.onOpenMap,
  });

  final bool timeTampered;
  final String apiAttendanceStatus;
  final String? apiCheckInTime;
  final String? apiCheckOutTime;
  final double? apiWorkingHours;
  final LatLng? coords;
  final bool isFake;
  final Function(LatLng)? onOpenMap;



  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Time Integrity status row
          _StatRowItem(
            icon: Icons.verified_user_rounded,
            label: 'أمان ومزامنة وقت الهاتف',
            value: timeTampered ? 'غير متطابق (تلاعب)' : 'آمن ومطابق للسيرفر',
            valueColor: timeTampered ? AppColors.error : AppColors.success,
          ),

          if (apiAttendanceStatus == 'CHECKED_IN' || apiAttendanceStatus == 'COMPLETED') ...[
            const Divider(),
            _StatRowItem(
              icon: Icons.alarm_on_rounded,
              label: 'وقت تسجيل الحضور اليومي',
              value: apiCheckInTime != null && apiCheckInTime!.isNotEmpty ? apiCheckInTime! : '--:--',
              valueColor: AppColors.textPrimary,
            ),
          ],

          if (apiAttendanceStatus == 'COMPLETED') ...[
            const Divider(),
            _StatRowItem(
              icon: Icons.alarm_off_rounded,
              label: 'وقت تسجيل الانصراف اليومي',
              value: apiCheckOutTime != null && apiCheckOutTime!.isNotEmpty ? apiCheckOutTime! : '--:--',
              valueColor: AppColors.textPrimary,
            ),
            const Divider(),
            _StatRowItem(
              icon: Icons.work_history_rounded,
              label: 'ساعات العمل اليومية',
              value: apiWorkingHours != null ? '${apiWorkingHours!.toStringAsFixed(1)} ساعة' : '--:--',
              valueColor: AppColors.primary,
            ),
          ],

          if (coords != null) ...[
            const Divider(),
            Row(
              children: [
                Icon(
                  isFake ? Icons.gps_off_rounded : Icons.location_on_rounded,
                  size: 20,
                  color: isFake ? Colors.red : Colors.green,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isFake ? 'الموقع الجغرافي (وهمي/مزيف)' : 'الموقع الجغرافي (الحالي)',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${coords!.latitude.toStringAsFixed(6)}, ${coords!.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isFake) ...[
                        const SizedBox(height: 4),
                        const Text(
                          '* تنبيه: تم رصد محاكاة/تزييف للموقع الجغرافي على الهاتف.',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: Colors.red,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.map_rounded, color: isFake ? Colors.red : Colors.green),
                  onPressed: () => onOpenMap?.call(coords!),
                  tooltip: 'فتح في خرائط جوجل',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MapIconButton extends StatelessWidget {
  const _MapIconButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
            ),
            child: Icon(
              icon,
              color: color,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatRowItem extends StatelessWidget {
  const _StatRowItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _ZoneStatusCard extends StatelessWidget {
  const _ZoneStatusCard({
    required this.isInside,
    required this.zoneName,
  });

  final bool isInside;
  final String zoneName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isInside
            ? Colors.green.withValues(alpha: 0.08)
            : const Color(0xFFF59E0B).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isInside
              ? Colors.green.withValues(alpha: 0.3)
              : const Color(0xFFF59E0B).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isInside ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            color: isInside ? Colors.green : const Color(0xFFF59E0B),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isInside
                  ? 'أنت داخل نطاق المنطقة المحددة ($zoneName) - يمكنك تسجيل الحضور/الانصراف.'
                  : 'أنت خارج نطاق المنطقة المحددة ($zoneName) - يرجى الاقتراب لتتمكن من التسجيل.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isInside ? Colors.green : const Color(0xFFF59E0B),
                fontFamily: 'Cairo',
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
