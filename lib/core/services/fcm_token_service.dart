import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_config.dart';
import '../network/api_client.dart';

/// Service to handle retrieving device/app details and sending the FCM Token to the backend API.
class FcmTokenService {
  FcmTokenService._();

  /// Fetches FCM token, device model, app version, and calls the UpdateDeviceToken API.
  static Future<void> updateDeviceToken({
    required String jwtToken,
    required String phoneNumber,
  }) async {
    try {
      // 1. Get FCM Token
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        debugPrint('Error getting Firebase FCM token: $e');
      }

      // Fallback if token is null
      fcmToken ??= 'fcm_token_not_found';

      // 2. Determine Device Type
      final String deviceType = Platform.isAndroid ? 'android' : 'ios';

      // 3. Get Device Name/Model
      String deviceName = Platform.isAndroid ? 'Android Device' : 'iOS Device';
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          // E.g., "Samsung SM-G998B"
          deviceName = '${androidInfo.manufacturer} ${androidInfo.model}';
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceName = iosInfo.name; // E.g., "iPhone 15 Pro"
        }
      } catch (e) {
        debugPrint('Error getting Device Info: $e');
      }

      // 4. Get App Version
      String appVersion = AppConfig.appVersion;
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        appVersion = packageInfo.version;
      } catch (e) {
        debugPrint('Error getting Package Info: $e');
      }

      // 5. Prepare API Request
      final url = '${AppConfig.baseUrl}/Users/UpdateDeviceToken';
      final body = {
        'deviceToken': fcmToken,
        'deviceType': deviceType,
        'deviceName': deviceName,
        'appVersion': appVersion,
        'phoneNumber': phoneNumber,
      };

      // 6. Execute POST Request via central logged client
      await ApiClient.post(
        url,
        headers: {
          'Authorization': 'Bearer $jwtToken',
        },
        body: body,
        timeout: const Duration(seconds: 10),
      );
    } catch (e, stackTrace) {
      debugPrint('Exception in updateDeviceToken service: $e');
      debugPrint('$stackTrace');
    }
  }
}
