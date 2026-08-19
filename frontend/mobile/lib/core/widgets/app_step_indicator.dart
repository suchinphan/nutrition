import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// แถบแสดงขั้นตอน 1/2/3 — วงกลมเลขขั้นตอน เชื่อมด้วยเส้น ขั้นที่ผ่านแล้ว/
/// ปัจจุบันเป็น teal500 ขั้นที่ยังไม่ถึงเป็น gray100
class AppStepIndicator extends StatelessWidget {
  final int currentStep; // 1-based
  final int totalSteps;
  final List<String>? stepLabels;

  const AppStepIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    this.stepLabels,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps * 2 - 1, (i) {
        if (i.isOdd) {
          final leftStepDone = ((i + 1) ~/ 2) < currentStep;
          return Expanded(
            child: Container(
              height: 2,
              color: leftStepDone ? AppColors.teal500 : AppColors.gray100,
            ),
          );
        }
        final step = i ~/ 2 + 1;
        final active = step <= currentStep;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? AppColors.teal500 : AppColors.gray100,
              ),
              child: Text(
                '$step',
                style: AppTextStyles.labelBold.copyWith(
                  color: active ? Colors.white : AppColors.gray600,
                ),
              ),
            ),
            if (stepLabels != null && step - 1 < stepLabels!.length) ...[
              const SizedBox(height: 4),
              Text(
                stepLabels![step - 1],
                style: AppTextStyles.caption.copyWith(
                  color: active ? AppColors.teal700 : AppColors.gray400,
                ),
              ),
            ],
          ],
        );
      }),
    );
  }
}
