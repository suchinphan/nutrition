"""Centralized age/BMI/TDEE/calorie-goal math. Single source of truth —
call these instead of re-deriving age/BMI/calories anywhere else."""
from datetime import date, datetime, timezone, timedelta

_BANGKOK = timezone(timedelta(hours=7))


def _bangkok_today() -> date:
    # date.today() ใช้ timezone ของเครื่อง server ตรงๆ — ถ้า server ไม่ได้ตั้ง
    # เป็น Asia/Bangkok อายุอาจเพี้ยนไป 1 วันช่วงใกล้เที่ยงคืน จึงคำนวณจากเวลา
    # กรุงเทพฯ ตรงๆ เสมอ (เหมือน get_thailand_time() ใน models.py)
    return datetime.now(_BANGKOK).date()


ACTIVITY_FACTORS = [
    (('ไม่ออกกำลัง', 'sedentary'), 1.2),
    (('1-3', 'light'), 1.375),
    (('3-5', 'moderate'), 1.55),
    (('6-7', 'heavy'), 1.725),
    (('หนักมาก', 'นักกีฬา', 'very_heavy'), 1.9),
]


def calc_age(date_of_birth) -> int | None:
    if not date_of_birth:
        return None
    today = _bangkok_today()
    return today.year - date_of_birth.year - (
        (today.month, today.day) < (date_of_birth.month, date_of_birth.day)
    )


def calc_bmi(weight, height) -> float | None:
    if not weight or not height:
        return None
    height_m = float(height) / 100
    if height_m <= 0:
        return None
    return round(float(weight) / (height_m ** 2), 1)


def bmi_status(bmi) -> str | None:
    if bmi is None:
        return None
    if bmi < 18.5:
        return 'ผอม'
    if bmi < 23:
        return 'ปกติ'
    if bmi < 25:
        return 'ท้วม/น้ำหนักเกิน'
    return 'อ้วน'


def calc_tdee(weight, height, age, gender, activity_level) -> int | None:
    if not weight or not height or not age or not gender:
        return None
    w, h, a = float(weight), float(height), int(age)
    is_female = str(gender).strip().lower() in ('หญิง', 'female', 'f')
    # สูตร Harris-Benedict ฉบับปัดเศษที่ hpc5.go.th (เว็บคำนวณ BMR ของกรม
    # อนามัย) ใช้จริง — ไม่ใช่สูตรต้นฉบับปี 1919 (66.5/13.75/5.003/6.755 และ
    # 655.0955/9.563/1.850/4.676) ที่เคยใช้มาก่อน ตรวจทาน BMR/TDEE ทั้ง 5
    # ระดับกิจกรรม x 2 เพศ กับผลลัพธ์จริงจากเว็บแล้วตรงกันเป๊ะด้วยสูตรนี้
    raw_bmr = (665 + 9.6 * w + 1.8 * h - 4.7 * a) if is_female \
        else (66 + 13.7 * w + 5 * h - 6.8 * a)
    activity_str = str(activity_level or '').lower()
    factor = 1.2
    for keys, f in ACTIVITY_FACTORS:
        if any(k in activity_str for k in keys):
            factor = f
    # เดิมคูณ factor กับ bmr ที่ปัดเศษเป็นจำนวนเต็มไปแล้ว (int(raw_bmr+0.5))
    # ทำให้ TDEE เพี้ยนไปได้ 1 kcal ในบางเคส (ผู้ใช้รายงานจริง: เพศชาย
    # น้ำหนัก 68 ส่วนสูง 170 อายุ 21 กิจกรรม 3-5 วัน/สัปดาห์ — เว็บได้ 2642
    # แต่ bmr ปัดแล้ว (1705) คูณ 1.55 ได้ 2642.75 ปัดขึ้นเป็น 2643 ผิด — ต้อง
    # คูณ factor กับ raw_bmr (ไม่ปัด) ก่อน แล้วค่อยปัด TDEE ทีเดียว ถึงจะตรง
    # กับเว็บทุกกรณี (ใช้ +0.5 แล้ว int() แทน round() ตรงๆ กัน Python
    # round-half-to-even ปัดเลข .5 ไม่ตรงกับฝั่ง Dart ของหน้า Flutter)
    return int(raw_bmr * factor + 0.5)


def calc_calories_goal(tdee, health_goal, gender=None) -> int | None:
    if tdee is None:
        return None
    offset = {'ลดน้ำหนัก': -500, 'รักษาน้ำหนัก': 0, 'เพิ่มน้ำหนัก': 500}.get(health_goal, 0)
    goal_calories = round(tdee) + offset
    if health_goal == 'ลดน้ำหนัก':
        # Safety floor กันแคลอรีต่ำเกินไปตอนลดน้ำหนัก — เดิม floor นี้มีแค่
        # ฝั่ง Flutter (bmi_calculator.dart's applyWeightGoal, ใช้แค่พรีวิว
        # ก่อนบันทึกจริง) ไม่มีที่ตัวเลขจริงที่ persist ลง DB เลย (บั๊กที่
        # เจอจริง) ทำให้ TDEE ต่ำๆ ได้ calories_goal บันทึกจริงต่ำกว่าเกณฑ์
        # ปลอดภัยได้ ทั้งที่หน้าพรีวิวโชว์ค่าที่ floor แล้วดูปลอดภัยกว่า
        floor = 1200 if gender == 'หญิง' else 1500
        goal_calories = max(goal_calories, floor)
    return goal_calories


def disease_adjustment_factor(chronic_diseases) -> float:
    """ปรับ TDEE ตามโรคประจำตัว — พอร์ตจาก bmi_calculator.dart's
    diseaseAdjustmentFactor() ให้ตรงกับฝั่ง Flutter เป๊ะ เดิม backend ไม่
    เคยเอาโรคประจำตัวมาคิดเลย (ใช้ TDEE ดิบเสมอ) ทำให้ calories_goal ที่
    บันทึกจริงไม่ตรงกับพรีวิวหน้าโปรไฟล์ที่ปรับตามโรคแล้ว"""
    if not chronic_diseases:
        return 0.0
    adjustments = 0.0
    for raw in chronic_diseases:
        d = str(raw).lower()
        if 'เบาหวาน' in d or 'diabetes' in d:
            adjustments -= 0.05
        if 'ความดัน' in d or 'hypertension' in d:
            adjustments -= 0.03
        if 'โรคไต' in d or 'ไต' in d:
            adjustments -= 0.05
        if 'มะเร็ง' in d:
            adjustments += 0.10
        if 'หืด' in d:
            adjustments -= 0.02
    return adjustments


def calc_calories_goal_custom(tdee, weight, target_weight, days, gender=None) -> int | None:
    """เป้าหมายแคลอรี่จากแผนน้ำหนักเป้าหมาย+จำนวนวันที่ผู้ใช้กำหนดเอง —
    พอร์ตจาก profile_page.dart's _dietRecommendedFor() ให้ backend คำนวณค่า
    ที่จะ persist ลง user.calories_goal (ที่แดชบอร์ด/มื้ออาหารใช้ต่อ) ตรง
    กับพรีวิวกล่อง "วางแผนพลังงาน" หน้าโปรไฟล์เป๊ะ แทนสูตร ±500 คงที่เดิม"""
    if tdee is None or weight is None or target_weight is None or days is None or days < 1:
        return None
    per_day = ((target_weight - weight) * 7700) / days
    raw = tdee + per_day
    return int(round(raw))


def calc_calories_from_macros(carbs_g, protein_g, fat_g) -> float:
    """Atwater general factors: 4 kcal/g carbs, 4 kcal/g protein, 9 kcal/g fat.
    Single source of truth for deriving calories from macros — every stored
    or displayed calorie figure that has known macros must trace back here."""
    return (carbs_g or 0) * 4 + (protein_g or 0) * 4 + (fat_g or 0) * 9


def score_food_candidate(item, target_calories, health_goal=None, chronic_diseases=None) -> float:
    """Rule-based nutrition score for ranking food_items — higher is better.
    Not a trained model: closeness to target_calories dominates, then basic
    dietary-guidance nudges (more protein for bulking, less sugar for
    diabetes, ...). Used by /api/ai/recommend instead of the old
    random.choice() 'AI'.
    item: dict with calories/protein_g/fat_g/fiber_g/sugar_g (None-safe)."""
    calories = float(item.get('calories') or 0)
    protein = float(item.get('protein_g') or 0)
    fat = float(item.get('fat_g') or 0)
    fiber = float(item.get('fiber_g') or 0)
    sugar = float(item.get('sugar_g') or 0)
    target = target_calories or 1

    score = -abs(calories - target) / target * 100
    score += fiber * 2 - sugar * 0.5

    if health_goal == 'ลดน้ำหนัก':
        score += protein * 1.0 - fat * 0.5
    elif health_goal == 'เพิ่มน้ำหนัก':
        score += protein * 1.5 + calories * 0.05
    else:
        score += protein * 0.5

    for d in (chronic_diseases or []):
        d = str(d).lower()
        if 'เบาหวาน' in d or 'diabetes' in d:
            score -= sugar * 2.5
        # ponytail: no sodium_mg column on food_items yet, so ความดันโลหิตสูง
        # can't be scored on sodium — add the column + this branch if needed
        if 'โรคไต' in d and protein > 15:
            score -= (protein - 15) * 1.0

    return round(score, 2)


# หมวดที่ "ไม่ควรแนะนำเลย" สำหรับโรคประจำตัวบางอย่าง ต่างจาก score_food_candidate
# ด้านบนที่แค่ลดคะแนน — เมนูของหวานที่หวานน้อยที่สุดในหมวดก็ยังโดนแนะนำให้คน
# เป็นเบาหวานอยู่ดีถ้าใช้แค่คะแนน (ผู้ใช้รายงานจริง) กรณีนี้ต้องกันทั้งหมวดเลย
# โรคอื่นยังไม่มีกฎห้ามทั้งหมวดเพราะไม่มีคอลัมน์โซเดียม/คอเลสเตอรอลให้ตัดสินได้
# ชัดเจนแบบเดียวกัน — ยังคงใช้ score_food_candidate ลดคะแนนแทนไปก่อน
DISEASE_BLOCKED_CATEGORIES = {
    'เบาหวาน': {'dessert'},
}


def blocked_category_reason(chronic_diseases, category):
    """คืนข้อความเหตุผลถ้าหมวดนี้ไม่ควรแนะนำเลยสำหรับโรคประจำตัวที่ผู้ใช้มี
    คืน None ถ้าไม่มีข้อห้าม"""
    for d in (chronic_diseases or []):
        dl = str(d).strip().lower()
        for disease_key, blocked in DISEASE_BLOCKED_CATEGORIES.items():
            if disease_key in dl and category in blocked:
                return f'คุณมีโรคประจำตัว{disease_key} ไม่แนะนำให้ทานเมนูหมวดนี้'
    return None
