import 'package:flutter/material.dart';
import '../models/meal_log.dart';
import '../services/auth_service.dart';
import '../services/food_item_service.dart';
import '../services/meal_log_service.dart';
import 'food_browser_page.dart';
import 'meal_select_sheet.dart';
import 'profile_page.dart';

/// ต้องกรอกข้อมูลส่วนตัว (เพศ/วันเกิด/น้ำหนัก/ส่วนสูง/ระดับกิจกรรม) เลือก
/// เป้าหมายสุขภาพ และกรอกกล่อง "วางแผนพลังงาน" (น้ำหนักเป้าหมาย+จำนวนวัน)
/// ให้ครบก่อนถึงจะบันทึกมื้ออาหารได้ — ไม่งั้น calories_goal จะเป็น null/
/// ไม่ถูกต้อง (คำนวณจาก BMR/TDEE ที่ต้องใช้ค่าพวกนี้ทั้งหมด) และมื้อที่บันทึก
/// จะไม่มีเป้าหมายอ้างอิงเลย — เดิมเช็คแค่มี health_goal เป็น string ไม่ว่าง
/// (เช่น "ลดน้ำหนัก") แต่ก่อนหน้านี้ปุ่ม "บันทึกเป้าหมาย" เคยบันทึกได้ทั้งที่
/// ไม่ได้กรอกน้ำหนักเป้าหมาย/จำนวนวันเลย (บั๊กที่แก้ไปแล้วที่ต้นทาง — ดู
/// ProfilePage._dietPlanValidationError) ทำให้บัญชีเก่าที่เคยบันทึกด้วยบั๊ก
/// นั้นค้างอยู่มี health_goal ตั้งไว้แต่ไม่มี target_weight/target_days เลย
/// ยังผ่านเงื่อนไขเดิมได้อยู่ (ผู้ใช้รายงานจริง) เช็ค target_weight/days ด้วย
/// เพื่อบังคับให้ต้องกรอกกล่องวางแผนพลังงานให้ครบก่อนเสมอ ไม่ว่าจะบันทึกไว้
/// ตอนไหนก็ตาม
bool hasCompleteProfileAndGoal() {
  final user = AuthService().user;
  if (user == null) return false;
  bool nonEmpty(String key) => (user[key]?.toString().trim().isNotEmpty) ?? false;
  final weight = double.tryParse(user['weight']?.toString() ?? '');
  final height = double.tryParse(user['height']?.toString() ?? '');
  final hasPersonal = nonEmpty('gender') &&
      nonEmpty('date_of_birth') &&
      nonEmpty('activity_level') &&
      weight != null && weight > 0 &&
      height != null && height > 0;
  final targetWeight = double.tryParse(user['health_goal_target_weight']?.toString() ?? '');
  final targetDays = int.tryParse(user['health_goal_target_days']?.toString() ?? '');
  final hasEnergyPlan = targetWeight != null && targetWeight > 0 && targetDays != null && targetDays > 0;
  return hasPersonal && nonEmpty('health_goal') && hasEnergyPlan;
}

Future<void> showIncompleteProfileDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ข้อมูลยังไม่ครบ'),
      content: const Text(
        'กรุณากรอกข้อมูลส่วนตัว (เพศ/วันเกิด/น้ำหนัก/ส่วนสูง/ระดับกิจกรรม) '
        'เลือกเป้าหมายสุขภาพ และกรอกกล่อง "วางแผนพลังงาน" '
        '(น้ำหนักเป้าหมาย/จำนวนวัน) แล้วกด "คำนวณ" + "บันทึกเป้าหมาย" ให้ครบก่อน '
        'ถึงจะบันทึกมื้ออาหารได้',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ปิด')),
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const ProfilePage(startInEditMode: true)),
            );
          },
          child: const Text('ไปกรอกข้อมูล'),
        ),
      ],
    ),
  );
}

/// จุดเข้าเดียวของ flow บันทึกมื้ออาหารทั้ง 3 ขั้นตอน (เลือกมื้อ -> เลือก
/// อาหาร -> เลือกขนาด+ยืนยัน) — เรียกจาก FAB "บันทึก" หรือปุ่ม "+ เพิ่มมื้อ
/// [ชื่อมื้อ]" ในหน้า dashboard (ผ่าน [preFilledMealType] เพื่อข้าม step 1)
/// [date] = null คือวันนี้ (ของเดิม) ระบุวันที่อื่นเพื่อกรอกย้อนหลัง (ดูปุ่ม
/// "บันทึกย้อนหลัง" ในหน้าหลัก/ประวัติ) — อนุญาตกรอกมื้อไหนเวลาไหนของวันนั้น
/// ก็ได้ (ไม่ล็อกตามช่วงเวลาอีกต่อไป ผู้ใช้ยืนยันชัดเจน) ยกเว้นวันในอนาคต
/// (backend ปฏิเสธเองอยู่แล้ว)
Future<void> startMealLogFlow(
  BuildContext context, {
  required MealLogService mealLogService,
  required FoodItemService foodItemService,
  MealType? preFilledMealType,
  DateTime? date,
}) async {
  if (!hasCompleteProfileAndGoal()) {
    await showIncompleteProfileDialog(context);
    return;
  }

  final logsResult = await mealLogService.fetchLogs(date: date ?? DateTime.now());
  final dayLogs = logsResult.when(ok: (l) => l, err: (_) => <MealLog>[]);
  if (!context.mounted) return;

  MealLog? log;
  if (preFilledMealType != null) {
    final result = await mealLogService.getOrCreateLog(mealType: preFilledMealType, date: date);
    if (!context.mounted) return;
    log = result.when(ok: (o) => o.log, err: (_) => null);
    if (log == null) return;
  } else {
    log = await showMealSelectSheet(context, mealLogService: mealLogService, todayLogs: dayLogs, date: date);
  }
  if (log == null || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FoodBrowserPage(
        mealLog: log!,
        foodItemService: foodItemService,
        mealLogService: mealLogService,
      ),
    ),
  );
}
