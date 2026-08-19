import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

String thousands(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return (n < 0 ? '-' : '') + buf.toString();
}

/// แถบแคลอรีสองชั้น: planned (สีอ่อน) เป็นพื้นหลัง, eaten (สีเข้ม) ทับด้านบน
/// ทั้งคู่วัดสัดส่วนเทียบกับ goal — ใช้แสดง "ทานจริงไปกี่ kcal จากเป้ากี่ kcal"
///
/// ค่าสีมี default สำหรับใช้บนพื้นขาว/อ่อน — หน้าที่วางบนพื้นสีเข้ม (เช่น
/// calorie hero card สีทึบ) override สีผ่าน [trackColor]/[plannedColor]/
/// [eatenColor]/[labelColor] ได้ และปิดข้อความบรรทัดบนด้วย [showLabel]: false
/// ถ้าหน้านั้นมีตัวเลขใหญ่ของตัวเองอยู่แล้ว
class AppCalorieBar extends StatelessWidget {
  final int eaten;
  final int planned;
  final int goal;
  final bool showLabel;
  final Color trackColor;
  final Color plannedColor;
  final Color eatenColor;
  final Color labelColor;
  final Color valueColor;

  const AppCalorieBar({
    super.key,
    required this.eaten,
    required this.planned,
    required this.goal,
    this.showLabel = true,
    this.trackColor = AppColors.gray100,
    this.plannedColor = AppColors.teal100,
    this.eatenColor = AppColors.teal500,
    this.labelColor = AppColors.gray600,
    this.valueColor = AppColors.gray900,
  });

  @override
  Widget build(BuildContext context) {
    final safeGoal = goal <= 0 ? 1 : goal;
    final plannedFraction = (planned / safeGoal).clamp(0.0, 1.0);
    final eatenFraction = (eaten / safeGoal).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('ทานจริง', style: AppTextStyles.bodySmall.copyWith(color: labelColor)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${thousands(eaten)} / ${thousands(goal)} kcal',
                  style: AppTextStyles.labelBold.copyWith(color: valueColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: trackColor),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: plannedFraction,
                  child: Container(color: plannedColor),
                ),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: eatenFraction,
                  child: Container(color: eatenColor),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
