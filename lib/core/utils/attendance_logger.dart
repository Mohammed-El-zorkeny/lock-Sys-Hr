import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '../../app/app_config.dart';
import '../storage/auth_storage.dart';
import 'device_security_helper.dart';

/// Utility class for logging HTTP requests/responses and state changes
/// to a local file on the device and printing them to the developer console.
class AttendanceLogger {
  AttendanceLogger._();

  static Future<File> get _logFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/attendance_logs.txt');
  }

  /// Appends standard text to the local attendance log file and prints to console.
  static Future<void> log(String text) async {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] $text\n';

    // Print to console
    if (kDebugMode) {
      // ignore: avoid_print
      print(logMessage);
    }

    try {
      final file = await _logFile;
      await file.writeAsString(logMessage, mode: FileMode.append);
      
      // Also print the file location so the developer knows where to retrieve it
      if (kDebugMode) {
        // ignore: avoid_print
        print('Logs saved to device path: ${file.path}');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Error writing log to file: $e');
      }
    }
  }

  /// Logs HTTP requests with format and parameters.
  static Future<void> logHttpRequest({
    required String url,
    required String method,
    required Map<String, String> headers,
    String? body,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('================= [HTTP REQUEST - CHECK STATUS] =================');
    buffer.writeln('--> $method: $url');
    buffer.writeln('Headers: $headers');
    if (body != null && body.isNotEmpty) {
      buffer.writeln('Body: $body');
    }
    buffer.writeln('================================================================');
    await log(buffer.toString());
  }

  /// Logs HTTP responses with format and body content.
  static Future<void> logHttpResponse({
    required String url,
    required int statusCode,
    required String body,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('================= [HTTP RESPONSE - CHECK STATUS] =================');
    buffer.writeln('<-- Status: $statusCode | URL: $url');
    buffer.writeln('Response Body: $body');
    buffer.writeln('==================================================================');
    await log(buffer.toString());
  }

  /// Logs screen access activities to the database via ORDS API in the background.
  static Future<void> logScreenActivity(String screenName) async {
    try {
      final token = await AuthStorage.getToken();
      if (token == null) return;

      final deviceUuid = await DeviceSecurityHelper.getDeviceUuid();
      final url = '${AppConfig.baseUrl}/Users/LogActivity';

      // Log locally first
      await log('Navigated to screen: $screenName');

      // Call API in the background
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'screenName': screenName,
          'deviceUuid': deviceUuid,
          'notes': 'Opened on device',
        }),
      ).timeout(const Duration(seconds: 5));

      if (kDebugMode) {
        print('Screen activity log response: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error logging screen activity: $e');
      }
    }
  }
}
