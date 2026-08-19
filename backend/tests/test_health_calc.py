"""Sanity checks for health_calc's BMR/TDEE math — the reference ranges
below (male 1,800-2,000 kcal, female 1,500-1,800 kcal) are the professor's
worked-example bounds for an office-worker archetype (age 25-35, low
activity). They are test fixtures, not a validation rule enforced on real
users — other activity levels (e.g. athletes) legitimately fall outside
this range and are NOT expected to match it."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from health_calc import calc_tdee, calc_calories_from_macros, score_food_candidate, blocked_category_reason


def test_tdee_male_office_worker_in_expected_range():
    # 65kg / 170cm / 30y / เพศชาย / ไม่ออกกำลัง (sedentary — desk job)
    tdee = calc_tdee(weight=65, height=170, age=30, gender='ชาย', activity_level='ไม่ออกกำลัง')
    assert 1800 <= tdee <= 2000, f'expected 1800-2000 kcal for male office worker, got {tdee}'


def test_tdee_female_office_worker_in_expected_range():
    # 55kg / 158cm / 28y / เพศหญิง / ไม่ออกกำลัง (sedentary — desk job)
    tdee = calc_tdee(weight=55, height=158, age=28, gender='หญิง', activity_level='ไม่ออกกำลัง')
    assert 1500 <= tdee <= 1800, f'expected 1500-1800 kcal for female office worker, got {tdee}'


def test_calc_calories_from_macros_atwater_factors():
    # 4 kcal/g carbs, 4 kcal/g protein, 9 kcal/g fat
    assert calc_calories_from_macros(carbs_g=45, protein_g=18, fat_g=9) == 333
    assert calc_calories_from_macros(carbs_g=0, protein_g=0, fat_g=0) == 0


# ทดสอบ BMR หญิงตรงๆ ด้วยค่าที่คำนวณมือ (ดู BUG-025 ใน BUG_REPORT.md) — ช่วง
# กว้าง 1500-1800 ด้านบนไม่สามารถแยกแยะระหว่างสูตรผิดกับสูตรถูกได้เลย
# เทสต์นี้เจาะจงเทียบค่าที่คำนวณมือจากสูตร Harris-Benedict ฉบับปัดเศษ
# (665/9.6/1.8/4.7) ที่ตรวจสอบแล้วว่าตรงกับผลลัพธ์จริงจากเว็บ hpc5.go.th
# ตรงๆ กัน จับ regression กลับไปใช้สูตรต้นฉบับปี 1919 ได้ทันที
def test_tdee_female_matches_hpc5_formula():
    # 55kg / 158cm / 28y / เพศหญิง / ไม่ออกกำลัง (sedentary, factor 1.2)
    # BMR = 665 + 9.6*55 + 1.8*158 - 4.7*28 = 1345.8 -> ปัด = 1346
    # TDEE = int(1346 * 1.2) = int(1615.2) = 1615
    tdee = calc_tdee(weight=55, height=158, age=28, gender='หญิง', activity_level='ไม่ออกกำลัง')
    assert tdee == 1615, f'expected 1615 kcal (hpc5.go.th formula), got {tdee}'


def test_score_food_candidate_prefers_closer_calorie_match():
    target = 500
    close = {'calories': 480, 'protein_g': 10, 'fat_g': 10, 'fiber_g': 2, 'sugar_g': 2}
    far = {'calories': 900, 'protein_g': 10, 'fat_g': 10, 'fiber_g': 2, 'sugar_g': 2}
    assert score_food_candidate(close, target) > score_food_candidate(far, target)


def test_score_food_candidate_penalizes_sugar_for_diabetes():
    item = {'calories': 500, 'protein_g': 10, 'fat_g': 10, 'fiber_g': 2, 'sugar_g': 30}
    plain = score_food_candidate(item, 500)
    diabetic = score_food_candidate(item, 500, chronic_diseases=['เบาหวาน'])
    assert diabetic < plain


def test_score_food_candidate_rewards_protein_when_bulking():
    low_protein = {'calories': 500, 'protein_g': 5, 'fat_g': 10, 'fiber_g': 2, 'sugar_g': 2}
    high_protein = {'calories': 500, 'protein_g': 30, 'fat_g': 10, 'fiber_g': 2, 'sugar_g': 2}
    assert score_food_candidate(high_protein, 500, health_goal='เพิ่มน้ำหนัก') > \
        score_food_candidate(low_protein, 500, health_goal='เพิ่มน้ำหนัก')


# ผู้ใช้รายงานจริง: เบาหวาน + หมวดของหวาน ยังโดน AI แนะนำอยู่ดี เพราะ
# score_food_candidate ด้านบนแค่ลดคะแนน ไม่ตัดออกทั้งหมวด — blocked_category_reason
# ต้องกันทั้งหมวดแทนสำหรับคู่โรค/หมวดที่ห้ามเด็ดขาด
def test_blocked_category_reason_blocks_dessert_for_diabetes():
    reason = blocked_category_reason(['เบาหวาน'], 'dessert')
    assert reason is not None and 'เบาหวาน' in reason


def test_blocked_category_reason_allows_dessert_without_diabetes():
    assert blocked_category_reason(['โรคไต'], 'dessert') is None
    assert blocked_category_reason([], 'dessert') is None


def test_blocked_category_reason_allows_other_categories_for_diabetes():
    assert blocked_category_reason(['เบาหวาน'], 'food') is None
    assert blocked_category_reason(['เบาหวาน'], 'drink') is None
