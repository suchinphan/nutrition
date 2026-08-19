import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

// จำนวน slot ขั้นต่ำที่ใช้คิดความกว้างแท่ง — เดิมหาร width ด้วย
// points.length ตรงๆ พอมีน้อยแท่ง (เช่นวันแรกของเป้าหมายใหม่ มีแค่ 1 จุด)
// แท่งเดียวได้ช่องกว้างเท่าทั้งกราฟ ยืดจนดูเป็นแท่งยักษ์ผิดสัดส่วน (ผู้ใช้
// รายงานจริง) คิดความกว้าง slot จากจำนวน slot ขั้นต่ำนี้เสมอแทน แท่งน้อยกว่า
// นี้จะเรียงชิดซ้ายแล้วเหลือที่ว่างด้านขวาไว้ ไม่ยืดเต็มความกว้าง
const _kMinChartSlots = 7;

double _slotWidth(double totalWidth, int pointCount) =>
    totalWidth / (pointCount < _kMinChartSlots ? _kMinChartSlots : pointCount);

// ระยะห่างแนวตั้ง — ผู้ใช้รายงานจริงว่าแท่ง/หัวข้อวัน/วันที่ชิดกันเกินไปจนดู
// อึดอัด ใช้ค่าคงที่ตั้งชื่อไว้ตรงนี้ที่เดียว (ไม่ใช่เลขลอยๆ +2 กระจายหลายจุด)
// เพื่อให้ _measureLabelAreaHeight (กันพื้นที่) กับ paint() (วาดจริง) ใช้เลข
// เดียวกันเป๊ะเสมอ แก้ระยะห่างแค่ตรงนี้ที่เดียวพอ
const _kBarToLabelGap = 6.0;
const _kLabelToSublabelGap = 3.0;

// วัดพื้นที่ label+sublabel ที่ต้องกันไว้จริง (แทนเดาค่าคงที่) — เรียกทั้งตอน
// build() ของ [AppBarChart] (กันความสูง SizedBox ให้พอ) และตอน paint() ของ
// [_BarChartPainter] (หาความสูงแท่งจริง) ต้องเป็นฟังก์ชันเดียวกันทั้งคู่
// ไม่งั้นตัวเลขไม่ตรงกัน — sublabel ยาว (เช่นวันที่เต็ม "04/08/2026") ตัด
// บรรทัดเป็น 2 บรรทัดได้ถ้าช่องแคบ (บาร์เยอะ) ค่าคงที่ตายตัวเดิม (28.0/16.0)
// ไม่เคยกันพื้นที่ให้บรรทัดที่ 2 เลย ข้อความเลยล้นไปทับ widget ถัดไปข้างล่าง
// (ผู้ใช้รายงานจริง)
double _measureLabelAreaHeight(List<AppBarChartPoint> points, double barSlotWidth) {
  var maxHeight = 0.0;
  for (final point in points) {
    final labelPainter = TextPainter(
      text: TextSpan(text: point.label, style: AppTextStyles.caption.copyWith(color: AppColors.gray400)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: barSlotWidth);
    var rowHeight = labelPainter.height;
    if (point.sublabel != null) {
      final subPainter = TextPainter(
        text: TextSpan(
          text: point.sublabel,
          style: AppTextStyles.caption.copyWith(color: AppColors.gray400, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: barSlotWidth);
      rowHeight += _kLabelToSublabelGap + subPainter.height;
    }
    if (rowHeight > maxHeight) maxHeight = rowHeight;
  }
  return maxHeight + _kBarToLabelGap;
}

/// จุดข้อมูลหนึ่งแท่งของ [AppBarChart]
/// - [value]: ค่าหลัก (เช่น eaten) วาดทับด้านบนสุดด้วย [barColor]
/// - [backgroundValue]: ค่าพื้นหลัง (เช่น planned) วาดเป็นชั้นล่างด้วยสีอ่อน
///   ถ้า null จะไม่วาดชั้นนี้ (โหมดแท่งเดียว)
/// - [muted]: true = วาด [value] ด้วยสีอ่อนแทนสีหลัก (เช่น วันที่ยังไม่มีข้อมูล)
/// - [tooltipLabel]: ข้อความเสริมโชว์คู่กับค่าตัวเลขใน tooltip ตอนแตะ (เช่น
///   วันที่เต็ม "4 ส.ค. 2026") — null ก็โชว์แค่ตัวเลขเหมือนเดิม (ไม่บังคับ
///   ใช้ทุกที่ที่เรียก AppBarChart)
/// - [sublabel]: บรรทัดที่ 2 ใต้ [label] (เช่นวันที่ N ของรอบเป้าหมาย) — null
///   ก็โชว์แค่บรรทัดเดียวเหมือนเดิม (ประวัติใช้คู่กับวันย่อ, กราฟ 7 วันของ
///   แดชบอร์ดไม่ใช้เลยไม่กระทบ)
class AppBarChartPoint {
  final String label;
  final double value;
  final double? backgroundValue;
  final bool muted;
  final String? tooltipLabel;
  final String? sublabel;

  const AppBarChartPoint({
    required this.label,
    required this.value,
    this.backgroundValue,
    this.muted = false,
    this.tooltipLabel,
    this.sublabel,
  });
}

/// Bar chart แบบ CustomPainter ล้วน (ไม่พึ่ง package กราฟ) — รองรับทั้งแท่ง
/// เดี่ยว (dashboard 7 วัน) และสองชั้น planned/eaten (ประวัติ) แตะแท่งเพื่อดู
/// tooltip ค่าตัวเลข
class AppBarChart extends StatefulWidget {
  final List<AppBarChartPoint> points;
  final double height;
  final Color barColor;
  final Color mutedBarColor;
  final Color backgroundBarColor;

  const AppBarChart({
    super.key,
    required this.points,
    this.height = 80,
    this.barColor = AppColors.teal500,
    this.mutedBarColor = AppColors.teal100,
    this.backgroundBarColor = AppColors.teal100,
  });

  @override
  State<AppBarChart> createState() => _AppBarChartState();
}

class _AppBarChartState extends State<AppBarChart> {
  int? _tappedIndex;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _handleTapUp(TapUpDetails details, double width) {
    if (widget.points.isEmpty) return;
    final slotWidth = _slotWidth(width, widget.points.length);
    // แตะในที่ว่างด้านขวา (เกินจำนวนแท่งจริง ตอนแท่งน้อยกว่า _kMinChartSlots
    // เรียงชิดซ้าย) ไม่ใช่แท่งไหนเลย — ไม่ต้องโชว์ tooltip
    if (details.localPosition.dx >= slotWidth * widget.points.length) return;
    final index = (details.localPosition.dx / slotWidth).floor().clamp(0, widget.points.length - 1);
    setState(() => _tappedIndex = index);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _tappedIndex = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return SizedBox(height: widget.height);
    }
    final maxValue = widget.points
        .map((p) => [p.value, p.backgroundValue ?? 0].reduce((a, b) => a > b ? a : b))
        .fold<double>(0, (a, b) => a > b ? a : b);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final barSlotWidth = _slotWidth(width, widget.points.length);
        final labelAreaHeight = _measureLabelAreaHeight(widget.points, barSlotWidth);
        return SizedBox(
          height: widget.height + labelAreaHeight,
          width: width,
          child: Stack(
            children: [
              GestureDetector(
                onTapUp: (d) => _handleTapUp(d, width),
                child: CustomPaint(
                  size: Size(width, widget.height + labelAreaHeight),
                  painter: _BarChartPainter(
                    chartBarHeight: widget.height,
                    points: widget.points,
                    maxValue: maxValue <= 0 ? 1 : maxValue,
                    barColor: widget.barColor,
                    mutedBarColor: widget.mutedBarColor,
                    backgroundBarColor: widget.backgroundBarColor,
                  ),
                ),
              ),
              if (_tappedIndex != null)
                _buildTooltip(width, widget.points[_tappedIndex!]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTooltip(double width, AppBarChartPoint point) {
    final barWidth = _slotWidth(width, widget.points.length);
    // เผื่อพื้นที่ทางขวามากขึ้นเมื่อมี tooltipLabel (ข้อความยาวกว่าตัวเลข
    // kcal เฉยๆ) กันกล่อง tooltip ล้นขอบขวาของกราฟ
    final reserve = point.tooltipLabel != null ? 140.0 : 70.0;
    final left = (barWidth * _tappedIndex!).clamp(0.0, width > reserve ? width - reserve : 0.0);
    return Positioned(
      left: left,
      top: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.gray900,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          point.tooltipLabel != null
              ? '${point.tooltipLabel} • ${point.value.toStringAsFixed(0)} kcal'
              : '${point.value.toStringAsFixed(0)} kcal',
          style: AppTextStyles.caption.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<AppBarChartPoint> points;
  final double maxValue;
  final Color barColor;
  final Color mutedBarColor;
  final Color backgroundBarColor;
  // ความสูงของพื้นที่แท่ง (ไม่รวม label) — คำนวณจาก _measureLabelAreaHeight
  // ตัวเดียวกับที่ AppBarChart.build() ใช้กันความสูง SizedBox ทั้งกล่องไว้แล้ว
  // (widget.height + labelAreaHeight) การใช้ค่านี้ตรงๆ แทนลบ label height
  // ออกจาก size.height เองอีกรอบ รับประกันว่า layout กับ paint ตรงกันเป๊ะเสมอ
  final double chartBarHeight;

  _BarChartPainter({
    required this.points,
    required this.maxValue,
    required this.barColor,
    required this.mutedBarColor,
    required this.backgroundBarColor,
    required this.chartBarHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barSlotWidth = _slotWidth(size.width, points.length);
    final barWidth = barSlotWidth * 0.5;
    final chartHeight = chartBarHeight;

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final slotLeft = barSlotWidth * i;
      final barLeft = slotLeft + (barSlotWidth - barWidth) / 2;

      // ผู้ใช้ขอ "กราฟสี่เหลี่ยมเลย" — เดิมมุมบนโค้งตามสัดส่วนความกว้างแท่ง
      // (barWidth * 0.3) ไม่ผูกกับความสูง พอแท่งเตี้ยแต่กว้าง มุมโค้งกิน
      // พื้นที่เกือบทั้งแท่งจนดูเป็นโดม ไม่ใช่สี่เหลี่ยม (ผู้ใช้รายงานจริง) —
      // วาดเป็นสี่เหลี่ยมมุมฉากตรงๆ แทน ไม่ปัดมุมเลย
      if (point.backgroundValue != null && point.backgroundValue! > 0) {
        final bgHeight = chartHeight * (point.backgroundValue! / maxValue).clamp(0.0, 1.0);
        canvas.drawRect(
          Rect.fromLTWH(barLeft, chartHeight - bgHeight, barWidth, bgHeight),
          Paint()..color = backgroundBarColor,
        );
      }

      final valueHeight = chartHeight * (point.value / maxValue).clamp(0.0, 1.0);
      if (valueHeight > 0) {
        canvas.drawRect(
          Rect.fromLTWH(barLeft, chartHeight - valueHeight, barWidth, valueHeight),
          Paint()..color = point.muted ? mutedBarColor : barColor,
        );
      }

      final textPainter = TextPainter(
        text: TextSpan(
          text: point.label,
          style: AppTextStyles.caption.copyWith(color: AppColors.gray400),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: barSlotWidth);
      textPainter.paint(
        canvas,
        Offset(slotLeft + (barSlotWidth - textPainter.width) / 2, chartHeight + _kBarToLabelGap),
      );

      if (point.sublabel != null) {
        // textAlign: center กันบรรทัดสั้นกว่า (เช่น "2026" แคบกว่า "04/08")
        // เอียงซ้ายภายในกรอบตอน sublabel มีหลายบรรทัด (ตัดขึ้นบรรทัดเองด้วย
        // \n — ดู history_page.dart) ไม่งั้นแต่ละบรรทัดจะไม่อยู่กึ่งกลางตรงกัน
        final subPainter = TextPainter(
          text: TextSpan(
            text: point.sublabel,
            style: AppTextStyles.caption.copyWith(color: AppColors.gray400, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout(maxWidth: barSlotWidth);
        subPainter.paint(
          canvas,
          Offset(
            slotLeft + (barSlotWidth - subPainter.width) / 2,
            chartHeight + _kBarToLabelGap + textPainter.height + _kLabelToSublabelGap,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.maxValue != maxValue || oldDelegate.chartBarHeight != chartBarHeight;
}
