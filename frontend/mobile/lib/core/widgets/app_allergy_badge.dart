import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// ป้ายเตือนสารก่อภูมิแพ้ — [allergenNames] ว่างหรือ null ห้ามแสดง widget
/// เลย (ไม่ใช่แสดงกล่องเปล่า) คืน SizedBox.shrink() แทน
class AppAllergyBadge extends StatelessWidget {
  final List<String>? allergenNames;

  const AppAllergyBadge({super.key, required this.allergenNames});

  @override
  Widget build(BuildContext context) {
    final names = allergenNames;
    if (names == null || names.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.coral50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⚠', style: TextStyle(fontSize: 12, color: AppColors.coral600)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              names.join(', '),
              style: AppTextStyles.caption.copyWith(color: AppColors.coral600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
