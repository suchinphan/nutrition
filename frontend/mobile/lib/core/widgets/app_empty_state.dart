import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// สถานะ "ไม่มีข้อมูล" มาตรฐาน — ต้องมี CTA เสมอ (ห้ามแสดงข้อความเปล่าๆ
/// ลอยเดี่ยวๆ ไม่มีทางออกให้ผู้ใช้กดต่อ)
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String ctaLabel;
  final VoidCallback onCta;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.ctaLabel,
    required this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.gray400),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.headingSmall.copyWith(color: AppColors.gray900),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray600),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onCta, child: Text(ctaLabel)),
          ],
        ),
      ),
    );
  }
}
