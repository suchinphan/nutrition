import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// จุดข้อมูลหนึ่งจุดของ [AppLineChart]
class AppLineChartPoint {
  final DateTime date;
  final double value;
  const AppLineChartPoint({required this.date, required this.value});
}

/// Line chart แบบ CustomPainter ล้วน (ไม่พึ่ง package กราฟ) — ใช้กับข้อมูล
/// แนวโน้มต่อเนื่อง (เช่นน้ำหนักย้อนหลัง) ต่างจาก [AppBarChart] ที่เหมาะกับ
/// ข้อมูลรายวันแยกกัน (เช่นแคลอรี)
class AppLineChart extends StatelessWidget {
  final List<AppLineChartPoint> points;
  final double height;
  final Color lineColor;
  final Color fillColor;

  const AppLineChart({
    super.key,
    required this.points,
    this.height = 140,
    this.lineColor = AppColors.teal500,
    this.fillColor = AppColors.teal50,
  });

  String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'ข้อมูลยังไม่พอสำหรับวาดกราฟ',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray400),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: height + 18,
          width: width,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(width, height),
                painter: _LineChartPainter(points: points, lineColor: lineColor, fillColor: fillColor),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: Text(_shortDate(points.first.date), style: AppTextStyles.caption.copyWith(color: AppColors.gray400)),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Text(_shortDate(points.last.date), style: AppTextStyles.caption.copyWith(color: AppColors.gray400)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<AppLineChartPoint> points;
  final Color lineColor;
  final Color fillColor;

  _LineChartPainter({required this.points, required this.lineColor, required this.fillColor});

  @override
  void paint(Canvas canvas, Size size) {
    final values = points.map((p) => p.value).toList();
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 0.01 ? 1.0 : (maxV - minV);
    // เผื่อขอบบน/ล่างนิดหน่อยกันเส้นแนบขอบกราฟเกินไป
    final paddedMin = minV - range * 0.15;
    final paddedRange = range * 1.3;

    double xFor(int i) => size.width * i / (points.length - 1);
    double yFor(double v) => size.height - ((v - paddedMin) / paddedRange) * size.height;

    final linePath = Path();
    final fillPath = Path();
    for (var i = 0; i < points.length; i++) {
      final x = xFor(i);
      final y = yFor(points[i].value);
      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(xFor(points.length - 1), size.height);
    fillPath.close();

    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // เน้นจุดค่าล่าสุดให้เห็นชัด
    final lastX = xFor(points.length - 1);
    final lastY = yFor(points.last.value);
    canvas.drawCircle(Offset(lastX, lastY), 4.5, Paint()..color = lineColor);
    canvas.drawCircle(
      Offset(lastX, lastY),
      4.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.lineColor != lineColor;
}
