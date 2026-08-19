import 'package:flutter/foundation.dart';

/// Event bus แบบง่าย — RootShell เก็บ Dashboard/History/Profile ไว้ใน
/// IndexedStack ตลอด (ไม่ rebuild ตอนสลับแท็บ) ถ้าไม่มีตัวนี้ หน้าที่ไม่ได้
/// active ตอนบันทึก/ทานแล้วจะไม่รู้ว่าข้อมูลเปลี่ยนจนกว่าจะ pull-to-refresh
/// เอง — service ที่แก้ meal_logs เรียก [changed] ทุกครั้งที่บันทึกสำเร็จ
/// ส่วนหน้าที่ต้องโชว์ข้อมูลสดก็ addListener ไว้ใน initState แล้วรีเฟรชเอง
class MealLogEvents extends ChangeNotifier {
  static final MealLogEvents instance = MealLogEvents._();
  MealLogEvents._();

  void changed() => notifyListeners();
}
