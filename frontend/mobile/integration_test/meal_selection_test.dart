// รันบนหน้าต่างจริง (ไม่ใช่แค่ widget test ในหน่วยความจำ):
//   flutter test integration_test/meal_selection_test.dart -d windows
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:frontend/router/app_router.dart';
import 'package:frontend/page/coming_soon_page.dart';
import 'package:frontend/page/meal_selection_page.dart';
import 'package:frontend/services/meal_selection_service.dart';
import 'package:frontend/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('เลือกมื้ออาหารและระยะเวลา end-to-end', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: const MealSelectionPage(service: MockMealSelectionService()),
      ),
    );

    // 1) สถานะ loading ก่อน (MockMealSelectionService หน่วง 700ms)
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    // รอ future ของ mock resolve
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 2) สรุปสุขภาพแสดงค่าจาก mock (bmi 22.4, เป้าแคลอรี 1850 kcal)
    expect(find.text('สรุปสุขภาพ'), findsOneWidget);
    expect(find.text('22.4'), findsOneWidget);
    expect(find.text('1850 kcal'), findsOneWidget);
    expect(find.text('ปกติ'), findsOneWidget); // ToneChip สถานะ BMI

    // 3) mock มี existingSelection (เช้า+กลางวัน, 14 วัน) — prefill มาแล้ว
    //    ปุ่ม "หน้าถัดไป" ต้อง enabled ตั้งแต่แรกเพราะมีมื้อเลือกไว้แล้ว
    FilledButton nextButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'หน้าถัดไป'));
    expect(nextButton().onPressed, isNotNull);
    expect(find.byTooltip('กรุณาเลือกมื้ออาหารอย่างน้อย 1 มื้อ'), findsNothing);

    // 4) ถอดมื้อที่ prefill ไว้ทั้ง 2 มื้อออก -> ปุ่มต้อง disabled + มี tooltip
    await tester.tap(find.text('เช้า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('กลางวัน'));
    await tester.pumpAndSettle();
    expect(nextButton().onPressed, isNull);
    expect(find.byTooltip('กรุณาเลือกมื้ออาหารอย่างน้อย 1 มื้อ'), findsOneWidget);

    // 5) เลือก "เย็น" กลับมา 1 มื้อ -> ปุ่มต้อง enabled อีกครั้ง
    await tester.tap(find.text('เย็น'));
    await tester.pumpAndSettle();
    expect(nextButton().onPressed, isNotNull);

    // 6) เปลี่ยนระยะเวลาเป็น 30 วัน ผ่าน dropdown จริง
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 วัน').last);
    await tester.pumpAndSettle();
    expect(find.text('30 วัน'), findsOneWidget);

    // 7) กด "หน้าถัดไป" -> ต้องไปหน้า ComingSoonPage ของ /meal/choose-food
    //    (ยังไม่มี widget จริงสำหรับหน้าเลือกเมนู ตามที่บันทึกไว้ใน
    //    lib/router/app_router.dart)
    await tester.tap(find.widgetWithText(FilledButton, 'หน้าถัดไป'));
    await tester.pump(); // เริ่ม submit เห็น spinner
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(ComingSoonPage), findsOneWidget);
    expect(find.text(AppRoutes.mealChooseFood), findsOneWidget);
  });
}
