import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/widgets/widgets.dart';

/// smoke test กันการ overflow ของ widget กลางชุดใหม่ทุกตัว — เรนเดอร์แต่ละ
/// widget ที่ความกว้าง 375px (iPhone SE ตัวที่แคบสุดที่แอปต้องรองรับ) แล้ว
/// เช็คว่าไม่มี exception (Flutter โยน FlutterError เมื่อ RenderFlex overflow)
Future<void> _pumpAt375(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(375, 812)),
        child: Scaffold(body: SizedBox(width: 375, child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('AppCalorieBar renders without overflow at 375px', (tester) async {
    await _pumpAt375(tester, const AppCalorieBar(eaten: 850, planned: 1200, goal: 1875));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppCalorieBar handles large numbers without overflow', (tester) async {
    await _pumpAt375(tester, const AppCalorieBar(eaten: 12345, planned: 12345, goal: 12345));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppNutrientChip renders without overflow at 375px', (tester) async {
    await _pumpAt375(
      tester,
      const Row(
        children: [
          AppNutrientChip(label: 'โปรตีน', value: 18, unit: 'g'),
          AppNutrientChip(label: 'คาร์บ', value: 45, unit: 'g'),
          AppNutrientChip(label: 'ไขมัน', value: 9, unit: 'g'),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppAllergyBadge with names renders without overflow', (tester) async {
    await _pumpAt375(
      tester,
      const AppAllergyBadge(allergenNames: ['กุ้ง', 'ไข่', 'น้ำปลา', 'ถั่วลิสง']),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppAllergyBadge with empty list renders nothing (SizedBox.shrink)', (tester) async {
    await _pumpAt375(tester, const AppAllergyBadge(allergenNames: []));
    expect(tester.takeException(), isNull);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('AppAllergyBadge with null renders nothing', (tester) async {
    await _pumpAt375(tester, const AppAllergyBadge(allergenNames: null));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppMealStatusTag renders both variants without overflow', (tester) async {
    await _pumpAt375(
      tester,
      const Row(
        children: [
          AppMealStatusTag(status: AppMealStatus.planned),
          AppMealStatusTag(status: AppMealStatus.eaten),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppFoodCard renders without overflow with a long name', (tester) async {
    await _pumpAt375(
      tester,
      AppFoodCard(
        categoryType: 'food',
        name: 'ข้าวผัดกุ้งใส่ไข่ดาวและผักสดตามฤดูกาลจานพิเศษ',
        calories: 350,
        allergenNames: const ['กุ้ง', 'ไข่'],
        trailing: const AppMealStatusTag(status: AppMealStatus.planned),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppSkeletonLoader renders all variants without overflow', (tester) async {
    for (final variant in AppSkeletonVariant.values) {
      await _pumpAt375(tester, AppSkeletonLoader(variant: variant));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('AppEmptyState renders without overflow', (tester) async {
    await _pumpAt375(
      tester,
      AppEmptyState(
        icon: Icons.receipt_long,
        title: 'ยังไม่มีประวัติการบันทึก',
        subtitle: 'เริ่มบันทึกมื้อแรกของวันนี้เพื่อดูสรุปที่นี่',
        ctaLabel: 'บันทึกมื้ออาหาร',
        onCta: () {},
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppErrorBanner renders without overflow with a long message', (tester) async {
    await _pumpAt375(
      tester,
      AppErrorBanner(
        message: 'เชื่อมต่อเครือข่ายไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่อีกครั้ง',
        onRetry: () {},
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
