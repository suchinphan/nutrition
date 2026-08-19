// Canonical BMI/BMR/TDEE math, ported 1:1 from backend/models.py's
// User.to_dict() so every screen (and the server) agrees on the same
// numbers. Previously personal_information_page.dart, Show_BMI_and_
// suggested_calories.dart, and choose_a_health_goal.dart each had their
// own slightly different formula.

double? calcBmi(double? weight, double? height) {
  if (weight == null || height == null || weight <= 0 || height <= 0) {
    return null;
  }
  final h = height / 100;
  return double.parse((weight / (h * h)).toStringAsFixed(2));
}

// เกณฑ์เอเชีย (18.5/23/25) ให้ตรงกับ backend/health_calc.py's bmi_status()
// เป๊ะ — เดิมใช้เกณฑ์สากล (18.5/25/30) ทำให้คนที่ BMI 23-25 เห็นสถานะ
// "ปกติ" ในหน้าพรีวิว Flutter แต่ backend (ค่าที่บันทึก/แสดงจริง) ถือว่า
// "ท้วม/น้ำหนักเกิน" ที่ BMI เดียวกัน (บั๊กที่เจอจริง)
String? bmiStatus(double? bmi) {
  if (bmi == null) return null;
  if (bmi < 18.5) return 'ผอม';
  if (bmi < 23) return 'ปกติ';
  if (bmi < 25) return 'ท้วม/น้ำหนักเกิน';
  return 'อ้วน';
}

// สูตร Harris-Benedict ฉบับปัดเศษให้ตรงกับ backend/health_calc.py และเว็บ
// hpc5.go.th (ไม่ใช่สูตรต้นฉบับปี 1919 ที่เคยใช้มาก่อน — ดู health_calc.py)
// ค่าดิบ (ไม่ปัดเศษ) — ใช้ทั้งใน calcBmr (ปัดเพื่อโชว์) และ calcTdee (เอาไป
// คูณ activity factor ต่อ) เดิม calcTdee รับค่า BMR ที่ปัดเป็นจำนวนเต็ม
// แล้วมาคูณ ทำให้ TDEE เพี้ยนไป 1 kcal ในบางเคส (ผู้ใช้รายงานจริง: เพศชาย
// น้ำหนัก 68 ส่วนสูง 170 อายุ 21 กิจกรรม 3-5 วัน/สัปดาห์ — เว็บได้ 2642 แต่
// ระบบคำนวณจาก BMR ที่ปัดแล้ว (1705) ได้ 2643 ส่วนอีกเคส (เพศหญิง กิจกรรม
// 1-3 วัน/สัปดาห์) กลับตรงกันพอดีเพราะบังเอิญเศษไม่เกิน .5 — ต้องคูณ factor
// จากค่าดิบก่อนปัด ถึงจะตรงกับเว็บทุกกรณี)
double? _rawBmr({required double? weight, required double? height, required int? age, required String? gender}) {
  if (weight == null || height == null || age == null || gender == null) {
    return null;
  }
  final genderStr = gender.trim().toLowerCase();
  final isFemale = genderStr == 'หญิง' || genderStr == 'female' || genderStr == 'f';
  return isFemale
      ? 665 + (9.6 * weight) + (1.8 * height) - (4.7 * age)
      : 66 + (13.7 * weight) + (5 * height) - (6.8 * age);
}

double? calcBmr({
  required double? weight,
  required double? height,
  required int? age,
  required String? gender,
}) {
  final rawBmr = _rawBmr(weight: weight, height: height, age: age, gender: gender);
  if (rawBmr == null) return null;
  return (rawBmr + 0.5).floorToDouble(); // ปัด BMR เป็นจำนวนเต็มให้ตรงกับเว็บ (แค่โชว์)
}

double _activityFactor(String? activity) {
  final a = (activity ?? '').toLowerCase();
  if (a.contains('ไม่ออกกำลัง') || a == 'sedentary') return 1.2;
  if (a.contains('1-3') || a == 'light') return 1.375;
  if (a.contains('3-5') || a == 'moderate') return 1.55;
  if (a.contains('6-7') || a == 'heavy') return 1.725;
  if (a.contains('หนักมาก') || a.contains('นักกีฬา') || a == 'very_heavy') return 1.9;
  return 1.2;
}

double? calcTdee({
  required double? weight,
  required double? height,
  required int? age,
  required String? gender,
  required String? activity,
}) {
  final rawBmr = _rawBmr(weight: weight, height: height, age: age, gender: gender);
  if (rawBmr == null) return null;
  return (rawBmr * _activityFactor(activity) + 0.5).floorToDouble();
}

// ปรับ TDEE ตามโรคประจำตัว (เปอร์เซ็นต์คงที่ต่อโรค เป็นค่าประมาณคร่าวๆ ไม่ใช่
// สูตรทางการแพทย์ที่แม่นยำ) — เดิมมีสูตรนี้ซ้ำกันอยู่แล้ว 2 ที่แบบไม่ตรงกัน
// เป๊ะ (choose_a_health_goal.dart กับ show_bmi_and_suggested_calories.dart)
// รวมเป็นจุดเดียวตรงนี้แทนตามหลักการของไฟล์นี้ (single source of truth)
double diseaseAdjustmentFactor(List<String>? diseases) {
  if (diseases == null || diseases.isEmpty) return 0.0;
  double adjustments = 0.0;
  for (final raw in diseases) {
    final d = raw.toLowerCase();
    if (d.contains('เบาหวาน') || d.contains('diabetes')) adjustments -= 0.05;
    if (d.contains('ความดัน') || d.contains('hypertension')) adjustments -= 0.03;
    if (d.contains('โรคไต') || d.contains('ไต')) adjustments -= 0.05;
    if (d.contains('มะเร็ง')) adjustments += 0.10;
    if (d.contains('หืด')) adjustments -= 0.02;
  }
  return adjustments;
}

/// Ported 1:1 from backend/api.py's compute_recommended_calories(): shifts
/// TDEE by a fixed 500 kcal/day toward the goal, clamped with a safety
/// floor (1500 male / 1200 female) on the losing side.
double? applyWeightGoal(double? tdee, String? gender, String? weightGoal) {
  if (tdee == null) return null;
  final goal = (weightGoal ?? '').trim();
  if (goal == 'ลดน้ำหนัก') {
    final isFemale = gender?.trim() == 'หญิง';
    final floor = isFemale ? 1200.0 : 1500.0;
    return (tdee - 500.0) < floor ? floor : (tdee - 500.0);
  }
  if (goal == 'เพิ่มน้ำหนัก') return tdee + 500.0;
  return tdee; // รักษาน้ำหนัก / unset
}
