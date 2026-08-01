import 'package:flutter/material.dart';

/// Central color palette for the Corporate Clean Theme.
/// HR / ERP oriented: calm, official, light surfaces.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFFC21C24); // أحمر أساسي زاهي وأنيق
  static const Color secondary = Color(
    0xFF8B1214,
  ); // أحمر داكن/مارون للتدرجات والبطاقات الداكنة
  static const Color accent = Color(
    0xFFE55B5F,
  ); // أحمر فاتح/مرجاني للتحديدات والتبويبات المحددة

  // Surfaces
  static const Color background = Color(
    0xFFF4F6F8,
  ); // خلفية رمادية باردة خفيفة جداً
  static const Color surface = Color(0xFFFFFFFF); // أسطح بيضاء
  static const Color card = Color(0xFFFFFFFF); // بطاقات بيضاء

  // Text
  static const Color textPrimary = Color(
    0xFF1E242B,
  ); // نص داكن فحمي مائل للأناقة
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Status
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFFE55B5F);

  // Lines & subtle
  static const Color border = Color(0xFFE5E7EB);
  static const Color divider = Color(0xFFF3F4F6);
  static const Color disabled = Color(0xFFD1D5DB);
  static const Color field = Color(0xFFF9FAFB);

  // Brand gradient (used for primary buttons, headers, FAB).
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [primary, secondary],
  );
}
