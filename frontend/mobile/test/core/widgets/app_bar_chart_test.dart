import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/app_bar_chart.dart';

void main() {
  // เดิมความกว้างแท่งคิดจาก totalWidth / points.length ตรงๆ — มีแค่ 1 จุด
  // (เช่นวันแรกของเป้าหมายสุขภาพที่เพิ่งเริ่ม) แท่งเดียวเลยยืดเต็มความกว้าง
  // กราฟทั้งหมด ดูเป็นแท่งยักษ์ผิดสัดส่วน (ผู้ใช้รายงานจริง) — ตอนนี้คิดจาก
  // slot ขั้นต่ำ 7 ช่องเสมอ แท่งน้อยกว่านั้นจะเรียงชิดซ้ายแทน เทสนี้ยืนยันผ่าน
  // พฤติกรรม tap-to-tooltip ซึ่งอิงตำแหน่ง slot เดียวกับที่วาดแท่งจริง
  testWidgets('single data point does not stretch its tap-hit area across the whole chart width', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 350,
          child: AppBarChart(points: [AppBarChartPoint(label: 'อ', value: 500)]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // แตะใกล้ขอบขวาของกราฟ (นอกช่วง slot แรกถ้าคิดจาก 7 slot ขั้นต่ำ) —
    // เดิม (หาร by points.length=1) จะตกอยู่ในแท่งเดียวที่ยืดเต็ม โชว์
    // tooltip ทันที ตอนนี้ต้องไม่โชว์เพราะเป็นพื้นที่ว่าง ไม่ใช่แท่งไหนเลย
    await tester.tapAt(const Offset(300, 40));
    await tester.pump();
    expect(find.textContaining('kcal'), findsNothing);

    // แตะใกล้ขอบซ้าย (อยู่ในแท่งแรกเสมอไม่ว่าจะคิดแบบไหน) ต้องโชว์ tooltip
    await tester.tapAt(const Offset(10, 40));
    await tester.pump();
    expect(find.textContaining('500 kcal'), findsOneWidget);
  });
}
