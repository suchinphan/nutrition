import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/page/meal_log_flow.dart';
import 'package:frontend/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('health goal without a saved energy plan (target weight/days) still blocks meal logging', () async {
    // เดิม hasCompleteProfileAndGoal() เช็คแค่มี health_goal เป็น string ไม่
    // ว่าง — บัญชีที่เคยบันทึกเป้าหมายตอนกล่อง "วางแผนพลังงาน" (น้ำหนัก
    // เป้าหมาย+จำนวนวัน) ยังไม่ได้กรอก (บั๊กเดิมที่แก้ไปแล้วฝั่ง
    // ProfilePage._dietPlanValidationError) เลยยังผ่านเงื่อนไขนี้ได้อยู่
    // ทั้งที่ไม่ได้กรอกครบจริง (ผู้ใช้รายงานจริง)
    await AuthService().saveUser({
      'id': '999',
      'gender': 'ชาย',
      'date_of_birth': '2000-01-01',
      'activity_level': 'ไม่ออกกำลังกายหรือออกกำลังกายน้อยมาก',
      'weight': '70',
      'height': '170',
      'health_goal': 'ลดน้ำหนัก',
    }, syncToServer: false);

    expect(hasCompleteProfileAndGoal(), isFalse);

    await AuthService().saveUser({
      'health_goal_target_weight': '65',
      'health_goal_target_days': '30',
    }, syncToServer: false);

    expect(hasCompleteProfileAndGoal(), isTrue);
  });
}
