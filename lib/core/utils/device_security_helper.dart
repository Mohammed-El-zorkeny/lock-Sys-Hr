import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

/// Helper class to extract a unique persistent identifier for the mobile device.
class DeviceSecurityHelper {
  DeviceSecurityHelper._();

  /// Returns a unique hardware-bound UUID for the device.
  static Future<String> getDeviceUuid() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // androidInfo.id is unique and stable across app reinstalls
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        // identifierForVendor is stable as long as at least one app from the vendor remains installed
        return iosInfo.identifierForVendor ?? 'ios_unknown_device';
      }
    } catch (_) {}
    return 'unknown_device';
  }
}
