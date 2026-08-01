import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local storage service for user authentication and details.
/// Uses [SharedPreferences] to store token and user session data.
class AuthStorage {
  AuthStorage._();

  static const String _keyToken = 'auth_token';
  static const String _keyUserData = 'user_data';

  /// Save token and user details to storage.
  static Future<void> saveSession({
    required String token,
    required Map<String, dynamic> user,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUserData, jsonEncode(user));
  }

  /// Clear session data (for logout).
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUserData);
  }

  /// Check if a user session is active.
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_keyToken);
  }

  /// Get active JWT token.
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  /// Get parsed user data.
  static Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyUserData);
    if (jsonStr == null) return null;
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // Nested property helpers

  /// Retrieve localized employee name (Arabic).
  static Future<String> getEmployeeNameAr() async {
    final userData = await getUserData();
    if (userData == null) return '';
    final employee = userData['employee'];
    if (employee != null && employee['nameAr'] != null) {
      return employee['nameAr'].toString();
    }
    if (userData['userNameAr'] != null) {
      return userData['userNameAr'].toString();
    }
    return userData['username']?.toString() ?? '';
  }

  /// Retrieve localized employee name (English).
  static Future<String> getEmployeeNameEn() async {
    final userData = await getUserData();
    if (userData == null) return '';
    final employee = userData['employee'];
    if (employee != null && employee['nameEn'] != null) {
      return employee['nameEn'].toString();
    }
    if (userData['userNameEn'] != null) {
      return userData['userNameEn'].toString();
    }
    return userData['username']?.toString() ?? '';
  }

  /// Retrieve localized department name (Arabic).
  static Future<String> getDepartmentNameAr() async {
    final userData = await getUserData();
    if (userData == null) return '';
    final employee = userData['employee'];
    if (employee != null && employee['department'] != null) {
      return employee['department']['nameAr']?.toString() ?? '';
    }
    return '';
  }

  /// Retrieve localized department name (English).
  static Future<String> getDepartmentNameEn() async {
    final userData = await getUserData();
    if (userData == null) return '';
    final employee = userData['employee'];
    if (employee != null && employee['department'] != null) {
      return employee['department']['nameEn']?.toString() ?? '';
    }
    return '';
  }

  /// Retrieve localized job title (Arabic).
  static Future<String> getJobTitleAr() async {
    final userData = await getUserData();
    if (userData == null) return '';
    final employee = userData['employee'];
    if (employee != null && employee['jobTitle'] != null) {
      return employee['jobTitle']['nameAr']?.toString() ?? '';
    }
    return '';
  }

  /// Retrieve localized job title (English).
  static Future<String> getJobTitleEn() async {
    final userData = await getUserData();
    if (userData == null) return '';
    final employee = userData['employee'];
    if (employee != null && employee['jobTitle'] != null) {
      return employee['jobTitle']['nameEn']?.toString() ?? '';
    }
    return '';
  }

  /// Retrieve employee code.
  static Future<String> getEmployeeCode() async {
    final userData = await getUserData();
    if (userData == null) return '';
    final employee = userData['employee'];
    if (employee != null) {
      return employee['employeeCode']?.toString() ?? '';
    }
    return '';
  }

  /// Retrieve employee ID.
  static Future<int?> getEmployeeId() async {
    final userData = await getUserData();
    if (userData == null) return null;
    final employee = userData['employee'];
    if (employee != null) {
      if (employee['employeeId'] != null) {
        return int.tryParse(employee['employeeId'].toString());
      }
      if (employee['id'] != null) {
        return int.tryParse(employee['id'].toString());
      }
    }
    if (userData['employeeId'] != null) {
      return int.tryParse(userData['employeeId'].toString());
    }
    return null;
  }

  /// Retrieve company ID.
  static Future<int?> getCompanyId() async {
    final userData = await getUserData();
    if (userData == null) return null;
    final employee = userData['employee'];
    if (employee != null && employee['companyId'] != null) {
      return int.tryParse(employee['companyId'].toString());
    }
    if (userData['companyId'] != null) {
      return int.tryParse(userData['companyId'].toString());
    }
    return null;
  }

  /// Retrieve branch ID.
  static Future<int?> getBranchId() async {
    final userData = await getUserData();
    if (userData == null) return null;
    final employee = userData['employee'];
    if (employee != null && employee['branchId'] != null) {
      return int.tryParse(employee['branchId'].toString());
    }
    if (userData['branchId'] != null) {
      return int.tryParse(userData['branchId'].toString());
    }
    return null;
  }


  /// Retrieve hire date.
  static Future<String> getHireDate() async {
    final userData = await getUserData();
    if (userData == null) return '';
    final employee = userData['employee'];
    if (employee != null) {
      return employee['hireDate']?.toString() ?? '';
    }
    return '';
  }

  /// Retrieve localized site name (Arabic).
  static Future<String> getSiteNameAr() async {
    final userData = await getUserData();
    if (userData == null) return '';
    final employee = userData['employee'];
    if (employee != null && employee['site'] != null) {
      return employee['site']['nameAr']?.toString() ?? '';
    }
    return '';
  }

  /// Retrieve email.
  static Future<String> getEmail() async {
    final userData = await getUserData();
    return userData?['email']?.toString() ?? '';
  }

  /// Retrieve phone number.
  static Future<String> getPhone() async {
    final userData = await getUserData();
    return userData?['phone']?.toString() ?? '';
  }

  /// Retrieve username.
  static Future<String> getUsername() async {
    final userData = await getUserData();
    return userData?['username']?.toString() ?? '';
  }

  /// Update the isChangePassword flag inside stored user data to 0.
  static Future<void> clearChangePasswordFlag() async {
    final userData = await getUserData();
    if (userData != null) {
      userData['isChangePassword'] = 0;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUserData, jsonEncode(userData));
    }
  }

  /// Retrieve whether employee is restricted to site location (defaults to true).
  static Future<bool> isLocationRequired() async {
    final userData = await getUserData();
    if (userData == null) return true;
    final employee = userData['employee'];
    if (employee != null && employee['checkLocation'] != null) {
      return employee['checkLocation'].toString().toUpperCase() != 'N';
    }
    return true;
  }

  /// Retrieve whether user is allowed to access Attendance/Check-In feature (defaults to true).
  static Future<bool> isAttendanceAllowed() async {
    final userData = await getUserData();
    if (userData == null) return true;
    if (userData['allowAttendance'] != null) {
      return userData['allowAttendance'].toString().toUpperCase() != 'N';
    }
    return true;
  }

  /// Retrieve whether user is allowed to access Dailies feature (defaults to true).
  static Future<bool> isDailiesAllowed() async {
    final userData = await getUserData();
    if (userData == null) return true;
    if (userData['allowDailies'] != null) {
      return userData['allowDailies'].toString().toUpperCase() != 'N';
    }
    return true;
  }
}
