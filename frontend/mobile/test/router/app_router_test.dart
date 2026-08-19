import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/page/coming_soon_page.dart';
import 'package:frontend/page/history_page.dart';
import 'package:frontend/router/app_router.dart';
import 'package:frontend/services/auth_service.dart';

void main() {
  test('onGenerateRoute returns null for AppRoutes.home', () {
    // ต้อง return null (ไม่ใช่ ComingSoonPage) เพราะ Flutter สร้าง route ให้
    // "/" เป็นขั้นแรกเสมอเมื่อ initialRoute ของ Navigator มีความยาว > 1
    // ตัวอักษร (เช่น initialRoute: '/history') — ถ้าคืน route จริงตรงนี้แทน
    // null มันจะถูกดันไปแอบอยู่ใต้หน้าเป้าหมายในสแตกเดียวกัน โผล่มาให้เห็น
    // ตอนกด back (บั๊กที่เจอจริงจากภาพหน้าจอ)
    final route = AppRouter.onGenerateRoute(
      const RouteSettings(name: AppRoutes.home),
    );
    expect(route, isNull);
  });

  testWidgets(
    'Navigator with initialRoute /history does not hide a ComingSoonPage("/") underneath',
    (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: AuthService(),
          child: MaterialApp(
            home: Navigator(
              initialRoute: AppRoutes.history,
              onGenerateRoute: AppRouter.onGenerateRoute,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(HistoryPage), findsOneWidget);
      // นี่คือ regression check ตรงๆ: ก่อนแก้บั๊ก ComingSoonPage("/") จะถูก
      // ดันเข้าไปในสแตกเดียวกันแบบมองไม่เห็น (อยู่ใต้ HistoryPage)
      expect(find.byType(ComingSoonPage), findsNothing);
    },
  );
}
