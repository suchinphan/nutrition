import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// แถบแจ้ง error สีคอรัลด้านบน พร้อมปุ่ม retry — ใช้จุดเดียวกันทุกหน้าที่
/// เรียก API แล้วพัง
class AppErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const AppErrorBanner({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: AppColors.coral50,
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.coral600, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.coral600),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: AppColors.coral600),
            child: const Text('ลองใหม่'),
          ),
        ],
      ),
    );
  }
}
