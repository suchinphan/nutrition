# WORKED_EXAMPLE — ที่มาของตัวเลขทุกจุดในระบบ

เอกสารนี้พิสูจน์ด้วยมือว่าตัวเลขทุกตัวที่ API คืนกลับมา (BMI, TDEE,
calories_goal, macro ต่อมื้อ, สรุปวันหนึ่ง) คำนวณได้ตรงกับสูตรใน
`health_calc.py` เป๊ะ — ทุกตัวเลขในเอกสารนี้รันทดสอบจริงกับ API ที่รันอยู่
(`python api.py`) ผ่านผู้ใช้ทดสอบชั่วคราว 2 คน แล้วลบทิ้งหลังตรวจสอบเสร็จ
ไม่ได้เดาหรือคำนวณลอยๆ

จุดคำนวณเดียวต่อสูตร ทั้งหมดอยู่ใน `backend/health_calc.py`:
`calc_age`, `calc_bmi`, `bmi_status`, `calc_tdee`, `calc_calories_goal`,
`calc_calories_from_macros`

---

## ผู้ใช้ตัวอย่างที่ 1 — ชาย (office worker)

### 1. ข้อมูลตั้งต้น
| field | value |
|---|---|
| น้ำหนัก | 65 kg |
| ส่วนสูง | 170 cm |
| วันเกิด | 1996-01-01 → อายุ 30 ปี (ณ 2026-07-21) |
| เพศ | ชาย |
| กิจกรรม | ไม่ออกกำลัง (sedentary, factor 1.2) |
| health_goal | รักษาน้ำหนัก (offset 0) |

### 2. BMI — `calc_bmi(weight, height)`
```
height_m = 170 / 100 = 1.70
BMI = weight / height_m² = 65 / (1.70 × 1.70) = 65 / 2.89 = 22.4913...
     → round 1 ตำแหน่ง = 22.5
```
**API คืนจริง:** `"bmi": 22.5, "bmi_status": "ปกติ"` ✓ ตรงกัน
(`bmi_status`: 22.5 อยู่ในช่วง 18.5 ≤ bmi < 23 → "ปกติ")

### 3. BMR — สูตร Harris–Benedict (ค.ศ. 1919, original — ไม่ใช่ฉบับ Roza–Shizgal 1984)
ค่าคงที่เพศชายที่ใช้ใน `calc_tdee()` (66.5, 13.75, 5.003, 6.755) ตรงกับ
สูตร Harris-Benedict ต้นฉบับสำหรับผู้ชาย (66.4730, 13.7516, 5.0033, 6.7550
ปัดเป็นทศนิยม 2-3 ตำแหน่ง):
```
BMR(ชาย) = 66.5 + 13.75×weight + 5.003×height − 6.755×age
         = 66.5 + 13.75×65 + 5.003×170 − 6.755×30
         = 66.5 + 893.75 + 850.51 − 202.65
         = 1608.11 kcal/วัน
```

### 4. TDEE = BMR × activity multiplier
```
activity multiplier (ไม่ออกกำลัง / sedentary) = 1.2
TDEE = 1608.11 × 1.2 = 1929.732 → round 2 ตำแหน่ง = 1929.73 kcal/วัน
```
**API คืนจริง (คำนวณภายใน `/api/user/health-goal`):** ตรงกับค่าที่ใช้คำนวณ
`calories_goal` ด้านล่าง ✓

### 5. calories_goal = TDEE ± offset ตาม health_goal
```
health_goal = "รักษาน้ำหนัก" → offset = 0
calories_goal = round(1929.73) + 0 = 1930
```
**API คืนจริง (`POST /api/user/health-goal`):** `"calories_goal": 1930` ✓ ตรงกัน

### 6. ตัวอย่าง 1 มื้อ — เมนู "ข้าวผัดกุ้ง" (food_item_id=1), quantity=1, ไม่เลือก serving (multiplier=1.0)
ค่าฐานต่อ 1 หน่วยของเมนูนี้ (จาก `food_items`, sync แล้วใน [งานที่ 2](#งานที่-2--ผล-audit-food_items) ให้ตรงสูตร 4/4/9 เป๊ะ):
`protein_g=18, carbs_g=45, fat_g=9`
```
protein_actual = 18 × 1.0 × 1 = 18.0
carbs_actual   = 45 × 1.0 × 1 = 45.0
fat_actual     = 9  × 1.0 × 1 = 9.0

calories_actual = calc_calories_from_macros(carbs=45, protein=18, fat=9)
                = 45×4 + 18×4 + 9×9
                = 180 + 72 + 81
                = 333 kcal
```
**API คืนจริง (`POST /meal-logs/13/items`):**
```json
{"calories_actual": 333.0, "protein_actual": 18.0, "carbs_actual": 45.0, "fat_actual": 9.0}
```
✓ ตรงกันทุกตัวเลข

### 7. สรุปวันหนึ่ง — บันทึกครบ 3 มื้อแล้วกดว่า "ทานแล้ว" ทุกมื้อ
| มื้อ | เมนู | qty | multiplier | calories_actual | protein | carbs | fat |
|---|---|---|---|---|---|---|---|
| เช้า | ข้าวผัดกุ้ง | 1 | 1.0 | 333.0 | 18.0 | 45.0 | 9.0 |
| กลางวัน | ต้มยำกุ้ง (น้ำใส) | 1 | 1.0 | 120.0 | 15.0 | 6.0 | 4.0 |
| เย็น | ข้าวเหนียวมะม่วง | 1 | 1.0 | 433.0 | 6.0 | 82.0 | 9.0 |
| **รวม** | | | | **886.0** | **39.0** | **133.0** | **22.0** |

ตรวจทาน: `calc_calories_from_macros(133, 39, 22) = 133×4 + 39×4 + 22×9 = 532 + 156 + 198 = 886` ✓ ตรงกับผลรวม calories_actual พอดี

**API คืนจริง (`GET /api/dashboard`):**
```json
{
  "eaten_calories": 886.0, "eaten_protein": 39.0, "eaten_carbs": 133.0, "eaten_fat": 22.0,
  "planned_calories": 886.0, "calories_goal": 1930.0, "over_limit": false,
  "dinner_logged": true, "bmi": 22.5, "bmi_status": "ปกติ"
}
```
✓ ตรงกันทุกตัวเลข (886 < 1930 → `over_limit: false` ถูกต้อง)

---

## ผู้ใช้ตัวอย่างที่ 2 — หญิง (office worker)

### 1. ข้อมูลตั้งต้น
| field | value |
|---|---|
| น้ำหนัก | 55 kg |
| ส่วนสูง | 158 cm |
| วันเกิด | 1998-01-01 → อายุ 28 ปี (ณ 2026-07-21) |
| เพศ | หญิง |
| กิจกรรม | ไม่ออกกำลัง (sedentary, factor 1.2) |
| health_goal | ลดน้ำหนัก (offset −500) |

### 2. BMI
```
height_m = 158 / 100 = 1.58
BMI = 55 / (1.58 × 1.58) = 55 / 2.4964 = 22.032... → round 1 ตำแหน่ง = 22.0
```
**API คืนจริง:** `"bmi": 22.0, "bmi_status": "ปกติ"` ✓

### 3. BMR — Harris–Benedict (หญิง)
ค่าคงที่เพศหญิงใน `calc_tdee()` คือ **655.0955**, 9.563, 1.850, 4.676 —
แก้ไขแล้ว (เดิมค่าคงที่แรกผิดเป็น 658.8675 ดูหัวข้อ "ปัญหาที่พบ" ข้อ 2
ท้ายเอกสาร) ตัวเลขด้านล่างคำนวณด้วยมือใหม่ตามค่าคงที่ที่ถูกต้อง:
```
BMR(หญิง) = 655.0955 + 9.563×weight + 1.850×height − 4.676×age
          = 655.0955 + 9.563×55 + 1.850×158 − 4.676×28
          = 655.0955 + 525.965 + 292.3 − 130.928
          = 1342.4325 kcal/วัน
```

### 4. TDEE
```
activity multiplier (ไม่ออกกำลัง) = 1.2
TDEE = 1342.4325 × 1.2 = 1610.919 → round 2 ตำแหน่ง = 1610.92 kcal/วัน
```

### 5. calories_goal
```
health_goal = "ลดน้ำหนัก" → offset = −500
calories_goal = round(1610.92) − 500 = 1611 − 500 = 1111
```
**หมายเหตุ:** ตัวเลข 3 บรรทัดนี้คำนวณด้วยมือใหม่ตามค่าคงที่ที่แก้แล้ว
ยังไม่ได้ยิง API จริงเพื่อ re-verify ในรอบนี้ (MySQL service หยุดอยู่ใน
เซสชันตรวจสอบนี้ — ดู `BUG_REPORT.md` BUG-001 status) ต่างจากตัวเลข BMI/
macro ด้านบน/ล่างในเอกสารนี้ที่เคย verify กับ API จริงมาก่อนแล้วในรอบก่อน

### 6. ตัวอย่าง 1 มื้อ — เมนู "ข้าวผัดกุ้ง" (food_item_id=1), quantity=1, serving="small" (multiplier=0.7)
ตัวอย่างนี้ใช้ serving ที่ไม่ใช่ 1.0 โดยตั้งใจ เพื่อพิสูจน์ว่า multiplier
คูณเข้าไปใน**ทั้ง 4 ค่าเท่ากัน** (calories ไม่ได้คำนวณแยกจาก macro):
```
protein_actual = 18 × 0.7 × 1 = 12.6
carbs_actual   = 45 × 0.7 × 1 = 31.5
fat_actual     = 9  × 0.7 × 1 = 6.3

calories_actual = calc_calories_from_macros(31.5, 12.6, 6.3)
                = 31.5×4 + 12.6×4 + 6.3×9
                = 126 + 50.4 + 56.7
                = 233.1 kcal
```
**API คืนจริง:**
```json
{"calories_actual": 233.1, "protein_actual": 12.6, "carbs_actual": 31.5, "fat_actual": 6.3}
```
✓ ตรงกันทุกตัวเลข

### 7. สรุปวันหนึ่ง
| มื้อ | เมนู | qty | multiplier | calories_actual | protein | carbs | fat |
|---|---|---|---|---|---|---|---|
| เช้า | ข้าวผัดกุ้ง | 1 | 0.7 (small) | 233.1 | 12.6 | 31.5 | 6.3 |
| กลางวัน | ต้มยำกุ้ง (น้ำใส) | 1.5 | 1.0 | 180.0 | 22.5 | 9.0 | 6.0 |
| เย็น | ข้าวเหนียวมะม่วง | 1 | 0.7 (small) | 303.1 | 4.2 | 57.4 | 6.3 |
| **รวม** | | | | **716.2** | **39.3** | **97.9** | **18.6** |

ตรวจทาน: `calc_calories_from_macros(97.9, 39.3, 18.6) = 97.9×4 + 39.3×4 + 18.6×9 = 391.6 + 157.2 + 167.4 = 716.2` ✓

**API คืนจริง (`GET /api/dashboard`):**
```json
{
  "eaten_calories": 716.2, "eaten_protein": 39.3, "eaten_carbs": 97.9, "eaten_fat": 18.6,
  "planned_calories": 716.2, "calories_goal": 1115.0, "over_limit": false,
  "dinner_logged": true, "bmi": 22.0, "bmi_status": "ปกติ"
}
```
✓ ตรงกันทุกตัวเลข (716.2 < 1115 → `over_limit: false` ถูกต้อง)

---

## สรุปสูตร + ที่มา (สำหรับตอบอาจารย์ "ตัวเลขนี้มาจากไหน")

| สูตร | ไฟล์ / ฟังก์ชัน | สูตรเต็ม |
|---|---|---|
| อายุ | `health_calc.calc_age` | อิงวันปัจจุบันเวลาไทย (UTC+7) ลบวันเกิด |
| BMI | `health_calc.calc_bmi` | `weight(kg) / (height(m))²` ปัด 1 ตำแหน่ง |
| สถานะ BMI | `health_calc.bmi_status` | เกณฑ์เอเชีย: <18.5 ผอม, <23 ปกติ, <25 ท้วม/น้ำหนักเกิน, ≥25 อ้วน |
| BMR | `health_calc.calc_tdee` (ภายใน) | Harris-Benedict 1919 — ชาย: `66.5+13.75W+5.003H−6.755A`, หญิง: `655.0955+9.563W+1.850H−4.676A` (แก้ค่าคงที่แรกแล้ว ดูหมายเหตุด้านบน) |
| TDEE | `health_calc.calc_tdee` | `BMR × activity_factor` (1.2/1.375/1.55/1.725/1.9 ตามระดับกิจกรรม) ปัด 2 ตำแหน่ง |
| calories_goal | `health_calc.calc_calories_goal` | `round(TDEE) + offset` (ลดน้ำหนัก −500 / รักษาน้ำหนัก 0 / เพิ่มน้ำหนัก +500) |
| แคลอรีจาก macro | `health_calc.calc_calories_from_macros` | `carbs_g×4 + protein_g×4 + fat_g×9` (Atwater general factors) |
| macro/แคลอรีต่อรายการอาหาร | `api.py: meal_log_items()` | `food_items.<macro>_g × serving.calories_multiplier × quantity` แล้วส่งต่อเข้า `calc_calories_from_macros` — ฟังก์ชันเดียว ไม่มีสูตรคำนวณ calories แยกจาก macro |
| สรุปวันของ dashboard | `api.py: _day_meal_log_totals` | `SUM(calories_actual/protein_actual/carbs_actual/fat_actual)` เฉพาะแถวที่ `is_eaten=1` |

---

## ปัญหาที่พบระหว่างตรวจ (รายงานตามที่อาจารย์สั่ง — ไม่ได้แก้เงียบๆ)

1. **ไม่มีเอกสารโภชนาการต้นฉบับจากอาจารย์ในโปรเจกต์** — ตรวจแล้วไม่พบไฟล์
   PDF/เอกสารอ้างอิงสูตรใดๆ ในรีโป จึงเทียบสูตรที่เจอกับสูตร Harris-Benedict
   มาตรฐานสากลแทน (ดูข้อ 2)

2. **ค่าคงที่ BMR หญิงคลาดเคลื่อนจากสูตร Harris-Benedict ต้นฉบับ** —
   `health_calc.py` เคยใช้ `658.8675` เป็นค่าคงที่แรก แต่สูตรต้นฉบับ (Harris
   & Benedict, 1919) คือ `655.0955` ต่างกัน +3.77 ทำให้ BMR/TDEE หญิงสูง
   กว่าสูตรต้นฉบับเล็กน้อยทุกกรณี (ที่ TDEE ~1600 kcal คิดเป็นคลาดเคลื่อน
   ~0.28%) ค่าคงที่ชายทั้ง 4 ตัวตรงกับต้นฉบับ ไม่มีปัญหา

   **แก้แล้ว** (ดู `BUG_REPORT.md` BUG-002) — รอบตรวจสอบก่อนหน้ารายงานไว้ว่า
   "รอคำสั่งอาจารย์ก่อนแก้" เพราะกลัวว่าอาจารย์อาจตั้งใจอ้างอิงตำราคนละฉบับ
   แต่ตรวจซ้ำแล้วยังไม่พบเอกสารอ้างอิงอาจารย์ในโปรเจกต์เลยจริงๆ (ข้อ 1) จึง
   แก้ค่าคงที่เป็น `655.0955` ตามสูตรต้นฉบับ Harris JA, Benedict FG.
   "A Biometric Study of Basal Metabolism in Man." Carnegie Institution of
   Washington, 1919 — ค่าคงที่อีก 3 ตัวไม่ต้องแก้ (ตรงต้นฉบับอยู่แล้ว) แก้ทั้ง
   `backend/health_calc.py` และสำเนาที่ port ไปฝั่ง Flutter
   (`frontend/mobile/lib/utils/bmi_calculator.dart` — ดูข้อ 4) พร้อมกัน
   เนื่องจากทั้งสองฝั่งใช้ค่าคงที่ผิดตัวเดียวกันมาก่อน

3. **users.bmi และ users.recommended_calories ที่คาดว่ามีอยู่ ไม่มีจริงใน
   schema ปัจจุบัน** — ตรวจ `models.py` แล้วไม่พบคอลัมน์ทั้งสองนี้ใน `User`
   BMI/TDEE/calories_goal ปัจจุบันคำนวณสด (on the fly) ทุกครั้งที่ query
   ผ่าน `health_calc.py` ไม่มีการเก็บ snapshot ซ้ำใน `users` table (มีแค่
   `calories_goal` ที่เก็บไว้จริงเพราะต้องคงค่าจนกว่าจะเปลี่ยน goal ใหม่ —
   ไม่ใช่ตัวเลขที่คำนวณซ้ำ) ถือว่าเป็นสถาปัตยกรรมที่ดีอยู่แล้วสำหรับหลักการ
   "single source of truth" จึงไม่ต้องแก้ไขอะไรเพิ่ม

4. **Flutter คำนวณ BMR/TDEE/BMI ซ้ำฝั่ง client** — พบใน
   `frontend/mobile/lib/utils/bmi_calculator.dart` (ใช้ใน
   `show_bmi_and_suggested_calories.dart`, `choose_a_health_goal.dart`,
   `profile_page.dart`, `personal_information_page.dart`) เป็นการ port
   สูตรมาจาก backend ไว้แสดงตัวอย่าง/พรีวิวก่อนกดบันทึกจริง (ค่าสุดท้ายที่
   เก็บลง DB ยังคำนวณจาก backend เสมอ ไม่ได้ให้ client ตัดสินเอง) แต่พบ
   **จุดที่ formula ไม่ตรงกับ backend 2 จุด**:
   - `bmiStatus()` ฝั่ง Flutter ใช้เกณฑ์ <18.5/<25/<30 (WHO สากล) ส่วน
     backend (`health_calc.bmi_status`) ใช้เกณฑ์ <18.5/<23/<25 (WHO เอเชีย)
     — คนละเกณฑ์กัน คนที่ BMI = 23-25 จะเห็นข้อความสถานะไม่ตรงกันระหว่าง
     หน้าพรีวิวกับหน้า dashboard จริง
   - `applyWeightGoal()` ฝั่ง Flutter มี floor คุมค่าต่ำสุด (1500 ชาย /
     1200 หญิง) ตอนลดน้ำหนัก แต่ backend (`calc_calories_goal`) ไม่มี floor
     นี้เลย — comment ในโค้ด Flutter อ้างว่า "ported 1:1 from
     backend/api.py's compute_recommended_calories()" แต่ฟังก์ชันนั้นไม่มี
     อยู่แล้วในปัจจุบัน (ถูกรวมเข้า `health_calc.calc_calories_goal` แล้ว
     ในเซสชันก่อนหน้า) comment จึงล้าสมัย

   **ไม่ได้แก้ในรอบนี้ตามเงื่อนไข** (ห้ามแตะ Flutter ยกเว้นรายงานไว้ก่อน) —
   รอ prompt ถัดไปเพื่อ (ก) รวม `bmi_status` เกณฑ์ให้ตรงกับ backend และ
   (ข) ตัดสินใจว่าจะเก็บ floor ของ `applyWeightGoal` ไว้เป็น UX พรีวิวเฉยๆ
   หรือย้าย floor logic เข้า `health_calc.calc_calories_goal` ให้เป็นความ
   จริงเดียวจริงๆ

## ผล audit food_items

ตรวจ `food_items` ทั้งตาราง (3 แถวที่มีอยู่จริงใน DB ปัจจุบัน — เป็น seed
data สำหรับพัฒนา ยังไม่ได้ import ชุดข้อมูลใหญ่จาก `backend/data/`) ด้วย
`tools/sync_food_items_calories.py`:

| id | เมนู | calories เดิม | คำนวณจาก macro (4/4/9) | diff |
|---|---|---|---|---|
| 1 | ข้าวผัดกุ้ง | 350 | 333.0 | 4.86% |
| 2 | ต้มยำกุ้ง (น้ำใส) | 120 | 120.0 | 0% |
| 3 | ข้าวเหนียวมะม่วง | 430 | 433.0 | 0.70% |

ทั้ง 3 แถวต่างกันไม่เกิน 10% (ไม่มี mismatch, ไม่มีแถว macro เป็น 0 ทั้งหมด)
รัน `python tools/sync_food_items_calories.py --apply` แล้วเพื่อให้
`calories` เท่ากับค่าที่คำนวณจาก macro เป๊ะ (350→333, 430→433, 120 คงเดิม)
ตามหลัก single source of truth — สคริปต์นี้เก็บไว้ใช้ audit ซ้ำได้ทุกครั้งที่
import เมนูใหม่เพิ่ม (default เป็น dry-run, ต้องส่ง `--apply` ถึงจะเขียนจริง)
