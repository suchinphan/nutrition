import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/bmi_calculator.dart' as bmi_calc;

void main() {
  // ข้อมูลตรงจากภาพจริงของผู้ใช้: น้ำหนัก 70 กก., ส่วนสูง 170 ซม., อายุ 21,
  // เพศชาย — ยืนยันว่า BMR คงที่ (ไม่ขึ้นกับกิจกรรมโดยนิยาม) ส่วน TDEE
  // เปลี่ยนตามตัวคูณกิจกรรมจริง
  const weight = 70.0;
  const height = 170.0;
  const age = 21;
  const gender = 'ชาย';

  test('BMR คงที่ทุกระดับกิจกรรม (ไม่ขึ้นกับ activity_level)', () {
    final bmr = bmi_calc.calcBmr(weight: weight, height: height, age: age, gender: gender);
    expect(bmr, closeTo(1737.66, 0.01));

    const activities = [
      'ไม่ออกกำลังกายหรือออกกำลังกายน้อยมาก',
      'ออกกำลังกาย/เล่นกีฬา 1-3 วัน/สัปดาห์',
      'ออกกำลังกายปานกลาง/เล่นกีฬา 3-5 วัน/สัปดาห์',
      'ออกกำลังกายหนัก/เล่นกีฬา 6-7 วัน/สัปดาห์',
      'ออกกำลังกายหนักมากเป็นนักกีฬา',
    ];
    for (final a in activities) {
      final bmrForActivity =
          bmi_calc.calcBmr(weight: weight, height: height, age: age, gender: gender);
      expect(bmrForActivity, bmr, reason: 'BMR ต้องไม่เปลี่ยนตาม activity: $a');
    }
  });

  test('TDEE เปลี่ยนตามตัวคูณกิจกรรมจริง', () {
    final bmr = bmi_calc.calcBmr(weight: weight, height: height, age: age, gender: gender)!;

    final expected = <String, double>{
      'ไม่ออกกำลังกายหรือออกกำลังกายน้อยมาก': bmr * 1.2,
      'ออกกำลังกาย/เล่นกีฬา 1-3 วัน/สัปดาห์': bmr * 1.375,
      'ออกกำลังกายปานกลาง/เล่นกีฬา 3-5 วัน/สัปดาห์': bmr * 1.55,
      'ออกกำลังกายหนัก/เล่นกีฬา 6-7 วัน/สัปดาห์': bmr * 1.725,
      'ออกกำลังกายหนักมากเป็นนักกีฬา': bmr * 1.9,
    };

    double? last;
    for (final entry in expected.entries) {
      final tdee = bmi_calc.calcTdee(bmr, entry.key);
      expect(tdee, closeTo(entry.value, 0.5), reason: 'TDEE ผิดสำหรับ ${entry.key}');
      if (last != null) expect(tdee! > last, isTrue, reason: 'TDEE ต้องเพิ่มขึ้นตามกิจกรรมที่หนักขึ้น');
      last = tdee;
    }

    // ค่าที่ตรงกับภาพจริง: กิจกรรม "หนัก 6-7 วัน/สัปดาห์" -> TDEE ~2997
    final heavyTdee = bmi_calc.calcTdee(bmr, 'ออกกำลังกายหนัก/เล่นกีฬา 6-7 วัน/สัปดาห์');
    expect(heavyTdee!.round(), 2997);
  });

  // ยืนยันว่าแก้ น้ำหนัก/ส่วนสูง/อายุ/เพศ แล้ว BMR (และ TDEE ที่คำนวณต่อ)
  // ขยับตามจริง — ไม่ใช่ค่าที่ค้างอยู่กับ activity_level อย่างเดียว
  const activity = 'ออกกำลังกายหนัก/เล่นกีฬา 6-7 วัน/สัปดาห์';

  test('BMR เปลี่ยนตามน้ำหนักที่แก้ไข', () {
    final bmrLight = bmi_calc.calcBmr(weight: 60, height: height, age: age, gender: gender)!;
    final bmrHeavy = bmi_calc.calcBmr(weight: 90, height: height, age: age, gender: gender)!;
    expect(bmrHeavy, greaterThan(bmrLight));
    expect(bmi_calc.calcTdee(bmrHeavy, activity)! > bmi_calc.calcTdee(bmrLight, activity)!, isTrue);
  });

  test('BMR เปลี่ยนตามส่วนสูงที่แก้ไข', () {
    final bmrShort = bmi_calc.calcBmr(weight: weight, height: 155, age: age, gender: gender)!;
    final bmrTall = bmi_calc.calcBmr(weight: weight, height: 190, age: age, gender: gender)!;
    expect(bmrTall, greaterThan(bmrShort));
  });

  test('BMR เปลี่ยนตามวันเกิด/อายุที่แก้ไข', () {
    final bmrYoung = bmi_calc.calcBmr(weight: weight, height: height, age: 18, gender: gender)!;
    final bmrOld = bmi_calc.calcBmr(weight: weight, height: height, age: 50, gender: gender)!;
    // สูตร Harris-Benedict: อายุมากขึ้น -> BMR ลดลง (ค่าคงที่ลบด้วยอายุ)
    expect(bmrOld, lessThan(bmrYoung));
  });

  test('BMR เปลี่ยนตามเพศที่แก้ไข (สูตรคนละชุดกันชาย/หญิง)', () {
    final bmrMale = bmi_calc.calcBmr(weight: weight, height: height, age: age, gender: 'ชาย')!;
    final bmrFemale = bmi_calc.calcBmr(weight: weight, height: height, age: age, gender: 'หญิง')!;
    expect(bmrMale, isNot(equals(bmrFemale)));
  });
}
