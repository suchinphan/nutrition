import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// กล่องแสดงค่า macronutrient หนึ่งตัว (โปรตีน/คาร์บ/ไขมัน ฯลฯ) — สีพื้นหลัง
/// อ่อน 10% ของ [color] ที่ผู้เรียกกำหนด (เช่น AppColors.blue400 สำหรับโปรตีน)
class AppNutrientChip extends StatelessWidget {
  final String label;
  final num value;
  final String unit;
  final Color color;

  const AppNutrientChip({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.color = AppColors.teal500,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTextStyles.caption.copyWith(color: color)),
          Text(
            '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}$unit',
            style: AppTextStyles.labelBold.copyWith(color: AppColors.gray900),
          ),
        ],
      ),
    );
  }
}
