import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

enum AppMealStatus { planned, eaten }

/// ป้ายสถานะรายการอาหาร — planned=amber "วางแผน", eaten=teal "ทานแล้ว"
class AppMealStatusTag extends StatelessWidget {
  final AppMealStatus status;

  const AppMealStatusTag({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final isEaten = status == AppMealStatus.eaten;
    final color = isEaten ? AppColors.teal500 : AppColors.amber500;
    final label = isEaten ? 'ทานแล้ว' : 'วางแผน';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w500)),
    );
  }
}
