// รันบนหน้าต่างจริง (ไม่ใช่แค่ widget test ในหน่วยความจำ):
//   flutter test integration_test/profile_page_diet_plan_test.dart -d windows
//
// ทดสอบ end-to-end กับ backend จริง (ต้องรัน backend/api.py ที่ 127.0.0.1:5000
// และมี user id 697 (username ponytailtest1, token ในโค้ดด้านล่าง) ที่กรอก
// โปรไฟล์ไว้แล้ว: เพศชาย น้ำหนัก 68, ส่วนสูง 170, เกิดวันที่ทำให้อายุ 21,
// กิจกรรม "ไม่ออกกำลังกายหรือออกกำลังกายน้อยมาก" — user นี้ถูก soft-delete
// (is_deleted=1) ไปแล้วหลังรันรอบก่อน ต้อง re-activate/สร้างใหม่ก่อนรันซ้ำ
//
// AuthService เป็น singleton ที่อ่าน/เขียน secure storage จริงของเครื่องนี้
// (เก็บ session ผู้ใช้จริงที่ล็อกอินอยู่) — สำรอง (snapshot) ค่าทั้งหมดไว้ก่อน
// แล้วคืนกลับใน finally เสมอ ไม่ให้ session ทดสอบไปทับของจริงค้างไว้
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/page/profile_page.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/storage_service.dart';
import 'package:frontend/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('โปรไฟล์: คำนวณ BMR/TDEE + วางแผนพลังงาน ให้ตัวเลขถูกต้อง', (tester) async {
    final storage = StorageService();
    final snapshot = await storage.readAll();
    final auth = AuthService();

    try {
      await auth.saveToken('slUVrFpGuFMCce7lvUKRP19cj98mgY5PJ3LhdRzpKkw');
      await auth.saveUser({
        'id': 697,
        'username': 'ponytailtest1',
        'name': 'Ponytail',
        'surname': 'Tester',
        'gender': 'ชาย',
        'date_of_birth': '2005-08-03',
        'weight': '68',
        'height': '170',
        'activity_level': 'ไม่ออกกำลังกายหรือออกกำลังกายน้อยมาก',
        'chronic_diseases': <String>[],
        'food_allergies': <String>[],
      }, syncToServer: false);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: MaterialApp(theme: AppTheme.light, home: const ProfilePage()),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 1) กล่อง "คำนวณ BMR / TDEE" ต้องยังไม่โชว์ตัวเลขจนกว่าจะกดคำนวณ + บันทึก
      //    (ฟิลด์เพศ/วันเกิด/น้ำหนัก/ส่วนสูง/ระดับกิจกรรม ถูก prefill จากโปรไฟล์
      //    ที่ตั้งไว้ข้างบนแล้ว ไม่ต้องกรอกใหม่)
      expect(find.text('คำนวณ BMR / TDEE'), findsOneWidget); // หัวข้อกล่อง
      expect(find.text('คำนวณ BMR'), findsOneWidget); // ปุ่มคำนวณ (แยกจากปุ่ม "คำนวณ" เฉยๆ ของกล่องวางแผนพลังงาน)
      expect(find.text('1705 kcal'), findsNothing);

      await tester.tap(find.text('คำนวณ BMR'));
      await tester.pumpAndSettle();
      expect(find.text('1705 kcal'), findsNothing); // แค่กดคำนวณยังไม่พอ ต้องกดบันทึกด้วย

      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('1705 kcal'), findsOneWidget); // BMR
      // การ์ดเป้าหมาย (ลด/รักษา/เพิ่มน้ำหนัก) ไม่พรีวิว kcal เองอีกต่อไปแล้ว
      // (ต้องกดคำนวณ+บันทึกก่อน — ดูขั้นตอนถัดไป) ดังนั้น "2046 kcal" ต้องมี
      // แค่จุดเดียวคือกล่อง TDEE เอง ไม่ใช่ซ้ำกับการ์ด "รักษาน้ำหนัก" แบบเดิม
      expect(find.text('2046 kcal'), findsOneWidget); // TDEE = 1705*1.2

      // 2) เลือกเป้าหมาย "ลดน้ำหนัก" -> กล่องวางแผนพลังงานต้องโผล่มา แต่การ์ด
      //    เองต้องยังไม่โชว์ kcal (ต้องกดคำนวณ + บันทึกก่อน)
      await tester.tap(find.text('ลดน้ำหนัก'));
      await tester.pumpAndSettle();
      expect(find.text('วางแผนพลังงาน'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'เป้าหมายน้ำหนักที่ต้องการ'), '60');
      await tester.enterText(find.widgetWithText(TextField, 'จำนวนวัน'), '30');
      await tester.tap(find.text('คำนวณ'));
      await tester.pumpAndSettle();

      // (60-68)*7700/30 = -2053.33 -> ต้องลด 2053, แนะนำ 2046-2053=-7 -> โดน floor เป็น 1500
      // ตอนนี้ยังไม่ได้กดบันทึก การ์ด "ลดน้ำหนัก" เองต้องยังไม่โชว์ตัวเลข ->
      // "1500 kcal" ต้องเจอแค่จุดเดียว (ในกล่องวางแผนพลังงาน)
      expect(find.text('พลังงานที่ต้องลดต่อวัน (kcal)'), findsOneWidget);
      expect(find.text('2053 kcal'), findsOneWidget);
      expect(find.text('พลังงานที่แนะนำต่อวัน (kcal)'), findsOneWidget);
      expect(find.text('1500 kcal'), findsOneWidget);

      // 2b) กด "บันทึกเป้าหมาย" -> หลังบันทึกสำเร็จ การ์ด "ลดน้ำหนัก" ต้องโชว์
      //     kcal เดียวกับกล่องวางแผนพลังงาน (1500 kcal) เป็นจุดที่ 2 แล้ว
      await tester.tap(find.text('บันทึกเป้าหมาย'));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('1500 kcal'), findsNWidgets(2));

      // 3) สลับไป "เพิ่มน้ำหนัก" -> ต้องเป็นกล่องใหม่ ไม่ใช่ค่าที่กรอกไว้ใน "ลดน้ำหนัก"
      await tester.tap(find.text('เพิ่มน้ำหนัก'));
      await tester.pumpAndSettle();
      final targetField = tester.widget<TextField>(find.widgetWithText(TextField, 'เป้าหมายน้ำหนักที่ต้องการ'));
      expect(targetField.controller!.text, isEmpty);

      await tester.enterText(find.widgetWithText(TextField, 'เป้าหมายน้ำหนักที่ต้องการ'), '75');
      await tester.enterText(find.widgetWithText(TextField, 'จำนวนวัน'), '30');
      await tester.tap(find.text('คำนวณ'));
      await tester.pumpAndSettle();

      // (75-68)*7700/30 = 1796.67 -> ต้องเพิ่ม 1797, แนะนำ 2046+1797=3843
      expect(find.text('พลังงานที่ต้องเพิ่มต่อวัน (kcal)'), findsOneWidget);
      expect(find.text('1797 kcal'), findsOneWidget);
      expect(find.text('3843 kcal'), findsOneWidget);

      // 4) กลับไป "ลดน้ำหนัก" -> ตัวเลขเดิม (60/30) ต้องยังอยู่ครบ ไม่ถูกล้าง
      //    "1500 kcal" เจอ 2 จุด: กล่องวางแผนพลังงาน + การ์ดเอง (บันทึกไปแล้วในขั้นตอน 2b)
      await tester.tap(find.text('ลดน้ำหนัก'));
      await tester.pumpAndSettle();
      expect(find.text('2053 kcal'), findsOneWidget);
      expect(find.text('1500 kcal'), findsNWidgets(2));
    } finally {
      await storage.deleteAll();
      for (final entry in snapshot.entries) {
        await storage.write(key: entry.key, value: entry.value);
      }
    }
  });
}
