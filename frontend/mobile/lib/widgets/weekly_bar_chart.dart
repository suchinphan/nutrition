import 'package:flutter/material.dart';
import '../models/dashboard_data.dart';
import '../theme/app_theme.dart';

/// แผนภูมิแท่งแคลอรี 7 วันย้อนหลัง (เขียว = ตามเป้า, แดง = เกินเป้า)
/// พร้อมเส้นประอ้างอิงเป้าหมายรายวัน
///
/// เลือกใช้ CustomPaint แทนไลบรารีกราฟอย่าง fl_chart เพราะรูปแบบกราฟที่ต้องการ
/// มีแค่แท่ง 7 แท่ง + เส้นเป้าหมาย วาดเองด้วย Flutter stdlib ได้ในโค้ดไม่กี่บรรทัด
/// ไม่คุ้มที่จะเพิ่ม dependency ใหม่ทั้งไลบรารีเพื่อสิ่งนี้ (ปัจจุบันโปรเจคนี้ยังไม่มี
/// fl_chart ติดตั้งอยู่) — ถ้าอนาคตต้องการกราฟซับซ้อนขึ้น (zoom, tooltip, เส้นหลายเส้น)
/// ค่อยพิจารณาเพิ่ม fl_chart ทีหลัง
class WeeklyBarChart extends StatelessWidget {
  final List<DailyCalorie> days; // ควรมี 7 รายการ เรียงเก่า -> ใหม่
  final double height;

  const WeeklyBarChart({super.key, required this.days, this.height = 140});

  static const _weekdayLabelsTh = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];

  @override
  Widget build(BuildContext context) {
    final captionStyle = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _WeeklyBarPainter(days: days),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Row(
          children: days
              .map(
                (d) => Expanded(
                  child: Center(
                    child: Text(
                      _weekdayLabelsTh[(d.date.weekday - 1) % 7],
                      style: captionStyle,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _WeeklyBarPainter extends CustomPainter {
  final List<DailyCalorie> days;
  _WeeklyBarPainter({required this.days});

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final maxValue = days
        .map((d) => d.consumedKcal > d.goalKcal ? d.consumedKcal : d.goalKcal)
        .reduce((a, b) => a > b ? a : b);
    final scale = maxValue <= 0 ? 0.0 : (size.height - 4) / maxValue;

    // เส้นเป้าหมาย: อ้างอิงจากเป้าของวันล่าสุด (เป้าหมายมักคงที่ทั้งสัปดาห์)
    final goalY = size.height - (days.last.goalKcal * scale);
    final goalPaint = Paint()
      ..color = AppColors.inkSoft.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    _drawDashedLine(canvas, Offset(0, goalY), Offset(size.width, goalY), goalPaint);

    final barWidth = size.width / days.length;
    final barPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final barHeight = (day.consumedKcal * scale).clamp(0.0, size.height);
      barPaint.color = day.isOverGoal ? AppColors.chili : AppColors.leaf;
      final rect = Rect.fromLTWH(
        i * barWidth + barWidth * 0.2,
        size.height - barHeight,
        barWidth * 0.6,
        barHeight,
      );
      // รัศมีมุมแท่งเล็กกว่า AppRadius.sm ตั้งใจ เพราะแท่งกราฟบางกว่าการ์ดทั่วไป
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        barPaint,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    var current = start.dx;
    while (current < end.dx) {
      canvas.drawLine(
        Offset(current, start.dy),
        Offset(current + dashWidth, start.dy),
        paint,
      );
      current += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _WeeklyBarPainter oldDelegate) =>
      oldDelegate.days != days;
}
