import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Single source of truth ของ typography ทั้งแอป — ห้าม hardcode fontSize/
/// fontWeight นอกไฟล์นี้ (ดู lib/core/theme/app_theme.dart / lib/core/widgets/*)
class AppTextStyles {
  AppTextStyles._();

  static const headingLarge = TextStyle(fontSize: 22, fontWeight: FontWeight.w500);
  static const headingMedium = TextStyle(fontSize: 18, fontWeight: FontWeight.w500);
  static const headingSmall = TextStyle(fontSize: 16, fontWeight: FontWeight.w500);

  static const bodyLarge = TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.6);
  static const bodyMedium = TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5);
  static const bodySmall = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);

  static const caption = TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.gray400);
  static const labelBold = TextStyle(fontSize: 13, fontWeight: FontWeight.w500);
}
