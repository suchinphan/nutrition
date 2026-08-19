import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// ครอบ icon เดิมด้วยตัวเลข badge มุมขวาบน — ไม่แสดงอะไรถ้า [count] เป็น 0
/// ใช้กับไอคอนบน bottom nav (เช่น โปรไฟล์) ที่ต้องโชว์จำนวนที่ยังไม่อ่าน
class AppBadgeIcon extends StatelessWidget {
  final Widget child;
  final int count;

  const AppBadgeIcon({super.key, required this.child, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final label = count > 99 ? '99+' : '$count';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -6,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              color: AppColors.coral400,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
