import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../storage/auth_storage.dart';

/// Central HTTP Client wrapper that automatically adds headers and prints clean request/response logs.
class ApiClient {
  ApiClient._();

  static final http.Client _client = http.Client();

  /// Perform a POST request with automatic headers and debug logging.
  static Future<http.Response> post(
    String url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = Uri.parse(url);

    // Get session token if stored
    final token = await AuthStorage.getToken();

    final requestHeaders = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      ...?headers,
    };

    final bodyString = body is String ? body : jsonEncode(body);

    // Dynamic, premium console logging for developers
    debugPrint('================= [HTTP REQUEST] =================');
    debugPrint('--> POST: $url');
    debugPrint('Headers: $requestHeaders');
    if (bodyString.isNotEmpty) {
      debugPrint('Body: $bodyString');
    }
    debugPrint('==================================================');

    try {
      final response = await _client.post(
        uri,
        headers: requestHeaders,
        body: bodyString,
      ).timeout(timeout);

      debugPrint('================= [HTTP RESPONSE] =================');
      debugPrint('<-- Status: ${response.statusCode} | URL: $url');
      debugPrint('Response Body: ${response.body}');
      debugPrint('===================================================');

      return response;
    } catch (e) {
      debugPrint('================= [HTTP EXCEPTION] =================');
      debugPrint('xxx Error: $e | URL: $url');
      debugPrint('====================================================');
      rethrow;
    }
  }

  /// Perform a GET request with automatic headers and debug logging.
  static Future<http.Response> get(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = Uri.parse(url);

    final token = await AuthStorage.getToken();

    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      ...?headers,
    };

    debugPrint('================= [HTTP REQUEST] =================');
    debugPrint('--> GET: $url');
    debugPrint('Headers: $requestHeaders');
    debugPrint('==================================================');

    try {
      final response = await _client.get(
        uri,
        headers: requestHeaders,
      ).timeout(timeout);

      debugPrint('================= [HTTP RESPONSE] =================');
      debugPrint('<-- Status: ${response.statusCode} | URL: $url');
      debugPrint('Response Body: ${response.body}');
      debugPrint('===================================================');

      return response;
    } catch (e) {
      debugPrint('================= [HTTP EXCEPTION] =================');
      debugPrint('xxx Error: $e | URL: $url');
      debugPrint('====================================================');
      rethrow;
    }
  }
}
