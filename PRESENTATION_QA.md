# PRESENTATION_QA — คำถามที่อาจารย์อาจถาม

เตรียมไว้ตอบสั้น กระชับ ตรงประเด็น ทุกคำตอบอ้างอิงโค้ดจริง (ไฟล์/บรรทัด)
ให้เปิดยืนยันสดได้ทันทีถ้าอาจารย์ขอดู

---

### 1. ทำไมรวม food_menus/drink_menus/dessert_menus เป็น `food_items` ตารางเดียว

เดิม (ก่อน schema v2) มี 3 ตารางแยกที่คอลัมน์แทบจะเหมือนกันทุกตัว
(calories/protein/carbs/fat/serving size/allergen) ต่างกันแค่ "ประเภท" —
ทำให้ทุกฟีเจอร์ที่ต้องใช้กับทั้ง 3 (ค้นหา, กรองแพ้อาหาร, เลือกขนาดเสิร์ฟ,
สลับเมนู) ต้องเขียนโค้ดซ้ำ 3 รอบ และ endpoint ฝั่ง client ต้องยิง 3 ครั้ง
ต่อการโหลดหน้าหนึ่งหน้า

**ทางแก้:** รวมเป็น `food_items` ตารางเดียว แล้วใช้คอลัมน์ `type` ใน
`food_categories` (`food`/`drink`/`dessert`) เป็นตัวแยกประเภทแทน — ยังกรอง
ได้ปกติผ่าน `?type=` (ดู `backend/api.py:644-646` `api_food_items()`) แต่
โค้ด serialize/allergy-check/serving-size logic ใช้ร่วมกันจุดเดียว
(`_serialize_food_item`, `backend/api.py:577`) และ endpoint เดียว
`GET /api/food-items` ฝั่ง Flutter (`FoodItem` model, `food_item.dart:27`)
ก็ parse type เดียวกันหมด ไม่ต้องมี `FoodMenu`/`DrinkMenu`/`DessertMenu`
model แยก 3 ชุดอีกต่อไป

---

### 2. ทำไมแคลอรีต้องคำนวณจาก macro (สูตร 4/4/9) แทนกรอกตรงๆ

ถ้ากรอก `calories` ตรงๆ แยกจาก `protein_g/carbs_g/fat_g` มีความเสี่ยงที่
ตัวเลขจะขัดกันเอง (เช่นกรอกแคลอรีผิดตอน import ข้อมูลจำนวนมาก) และเมื่อ
อาจารย์ถามที่มาของตัวเลข ระบบต้อง "อธิบายได้" — ถ้าแคลอรีเป็นค่าที่กรอกลอยๆ
ไม่มีสูตรอ้างอิง จะตอบไม่ได้ว่ามาจากไหน

**ทางแก้:** ใช้ Atwater general factors (คาร์บ 4 / โปรตีน 4 / ไขมัน 9
kcal ต่อกรัม — มาตรฐานสากลทางโภชนาการ) เป็นสูตรเดียวที่คำนวณแคลอรีทั้ง
ระบบ ผ่าน `health_calc.calc_calories_from_macros()`
(`backend/health_calc.py:76`) เรียกใช้ทั้งตอน sync `food_items.calories`
(`backend/tools/sync_food_items_calories.py`) และตอนคำนวณ
`meal_log_items.calories_actual` จริง (`backend/api.py:2637-2641`
`meal_log_items()`) — ตรวจแล้วพบว่าข้อมูลเดิมบางแถวคลาดเคลื่อนจากสูตรนี้
ไม่เกิน 5% (ดู `backend/WORKED_EXAMPLE.md` หัวข้อ "ผล audit food_items")
sync ให้ตรงเป๊ะแล้ว

---

### 3. ทำไมแอดมินดูประวัติผู้ใช้ได้อย่างเดียว แก้ไม่ได้

ตาราง `profile_audit_log` มีไว้พิสูจน์ว่า "ผู้ใช้กรอกอะไรเมื่อไหร่ด้วยตัวเอง"
— ถ้าแอดมินแก้ค่าพวกนี้ได้ (น้ำหนัก/ส่วนสูง/โรคประจำตัว/แพ้อาหาร) จะทำลาย
ความน่าเชื่อถือของ audit trail ทันที (ไม่รู้ว่าค่านั้นผู้ใช้กรอกเองหรือแอดมิน
แก้ให้) และข้อมูลสุขภาพเป็นข้อมูลส่วนบุคคลที่ผู้ใช้ควรเป็นเจ้าของ/ควบคุม
เพียงคนเดียว

**ยืนยันจากโค้ดจริง:** `backend/admin/admin_routes.py` มีแค่
`GET /admin/profile-history` (บรรทัด 54) ไม่มี PUT/PATCH/DELETE สำหรับ
`profile_audit_log` หรือฟิลด์โปรไฟล์ผู้ใช้เลยสักจุด ฝั่ง React
(`frontend/admin/src/api/profileHistory.js`) มีคอมเมนต์ระบุไว้ตรงๆ ว่า
"Read-only — there is intentionally no update/delete function here" สิ่ง
เดียวที่แอดมินทำกับ "บัญชี" ผู้ใช้ได้คือระดับบัญชี (ลบ/กู้คืน/แบน ผ่าน
`/admin/user/<id>/delete`, `/restore`) ไม่ใช่แก้เนื้อหาข้อมูลสุขภาพ

---

### 4. ทำไมเปลี่ยนรายงานปัญหาจาก AI chat เป็นกล่องข้อความ

**ข้อเท็จจริงจากการตรวจโค้ด:** ในโปรเจกต์นี้ไม่พบโค้ด AI/LLM integration
ใดๆ เลย (ไม่มี OpenAI SDK, ไม่มี endpoint เรียก AI ภายนอก) พบแค่ข้อความ
tooltip เดียวที่ยังเหลืออยู่ในโค้ดเก่าที่ orphan แล้ว
(`frontend/mobile/lib/main.dart:682` — `'รายงานปัญหา/คุยกับ AI'`) ซึ่งเป็น
label ของปุ่มที่เคยตั้งใจจะทำ แต่ไม่มีการ implement จริงหลงเหลืออยู่

ระบบที่ implement จริงคือ **ticket + กล่องข้อความ (chat แบบ polling)**:
`Report`/`ReportMessage` model (`backend/models.py:191-227`), ผู้ใช้ส่ง
ข้อความผ่าน `POST /api/reports/<id>/messages`, แอดมินตอบผ่าน
`POST /admin/reply`, ทั้งสองฝั่งเห็นข้อความใหม่ผ่าน polling ทุก 4 วินาที
(`ticket_chat_page.dart`, `ReportsPage.jsx`)

**เหตุผลที่เลือกทางนี้:** งานสุขภาพ/บัญชีผู้ใช้ต้องการคนตอบที่รับผิดชอบได้
จริง (accountability) — AI chat ตอบผิด/หลอน (hallucinate) เรื่องสุขภาพมี
ความเสี่ยงสูงกว่าการรายงาน bug ทั่วไป และ ticket แบบข้อความธรรมดาไม่มี
ต้นทุน API ภายนอก ไม่มี latency/ความไม่แน่นอนของ LLM ตรงไปตรงมากับขอบเขต
งานจริง (แจ้งบั๊ก/ขอความช่วยเหลือ ไม่ใช่ให้คำแนะนำสุขภาพเชิงลึกที่ต้องใช้
AI) — สอดคล้องกับหลัก "เขียนโค้ดเท่าที่จำเป็น" ที่ใช้ตลอดโปรเจกต์นี้

---

### 5. ระบบป้องกันข้อมูลแพ้อาหารตกหล่นยังไง

ใช้ junction table `food_allergens` (many-to-many ระหว่าง `food_items` ↔
`allergens`, `backend/models.py:135-139`) แทนการเก็บ allergen เป็น
text/JSON ในแถวเมนู — เพราะ (1) เมนูหนึ่งมีได้หลาย allergen พร้อมกัน (2)
allergen เดียวกันต้องตรงกับที่ผู้ใช้เลือกไว้แบบ exact match ไม่ใช่ fuzzy
text (3) เพิ่ม/แก้ allergen master list ทีเดียว มีผลกับทุกเมนูที่ผูกอยู่
ทันที ไม่ต้องไปแก้ทีละแถว

**กลไกตรวจตอนแสดงผลจริง:** `_serialize_food_item()`
(`backend/api.py:577-624`) — ทุกครั้งที่ดึงเมนู เทียบ
`{a.name for a in item.allergens}` กับ `user.food_allergies` (จาก
`users.food_allergies` JSON array) ถ้าตรงกันแม้แค่ 1 ตัว ตั้ง
`allergy_warning: true` พร้อม `warning` object แนบ code
`ALLERGEN_WARNING` กลับไปด้วย — เป็น **200 พร้อม flag** ไม่ใช่ error
บล็อกการดูเมนู (ผู้ใช้ยังเลือกได้ แค่เห็นคำเตือนก่อนตัดสินใจ) ทดสอบจริง
ด้วย `backend/tests/test_e2e_flow.py` ว่า warning ตรงเฉพาะเมนูที่มี
allergen ตรงจริง ไม่ปนเมนูอื่น

---

### 6. BMI ใช้เกณฑ์อะไร (WHO ทั่วไป หรือเกณฑ์เอเชีย)

**เกณฑ์เอเชีย (WHO Asia-Pacific)** — ตรวจจาก `health_calc.bmi_status()`
จริง (`backend/health_calc.py:42-51`):

```python
if bmi < 18.5: return 'ผอม'
if bmi < 23:   return 'ปกติ'
if bmi < 25:   return 'ท้วม/น้ำหนักเกิน'
return 'อ้วน'
```

จุดตัดที่ 23/25 คือเกณฑ์เอเชีย ไม่ใช่เกณฑ์ WHO สากลทั่วไป (ซึ่งใช้ 25/30)
— เหมาะกับกลุ่มผู้ใช้เป้าหมายของแอปที่เป็นคนไทย เพราะคนเอเชียมีความเสี่ยง
โรคที่สัมพันธ์กับไขมันสะสม (เบาหวาน/ความดัน) ที่ BMI ต่ำกว่ากลุ่มคนตะวันตก
ที่จุดตัดสากลถูกคิดขึ้นมา

**ข้อสังเกตที่พบระหว่างตรวจ (ต้องระวังตอบ):** ฝั่ง Flutter มีจุดคำนวณ BMI
พรีวิวซ้ำ (`frontend/mobile/lib/utils/bmi_calculator.dart:15-21`) ที่ยัง
ใช้เกณฑ์สากล 18.5/25/30 อยู่ — ใช้แค่หน้าพรีวิวก่อนบันทึก (หน้าที่ orphan
ไปแล้วเป็นส่วนใหญ่ ดู `ARCHITECTURE.md`) ค่าที่ dashboard แสดงจริงมาจาก
backend เกณฑ์เอเชียเสมอ แต่ถ้าอาจารย์เจอหน้าพรีวิวเก่าที่ยังโชว์ผลต่างกัน
ให้ตอบตรงๆ ว่าเป็นจุดที่รู้อยู่แล้วว่าไม่ตรงกัน รอแก้ในรอบถัดไป (รายงานไว้
แล้วใน `ARCHITECTURE.md` และ `backend/WORKED_EXAMPLE.md`)

---

### 7. ทำไมแจ้งเตือนมื้ออาหารไม่ทำงานถ้าไม่เปิดแอป

**ยอมรับตรงๆ ว่าเป็นข้อจำกัดจริง ไม่ใช่บั๊กที่ซ่อนไว้:** การตั้งเวลาแจ้งเตือน
(`NotificationHelper.scheduleMealReminders()`,
`frontend/mobile/lib/core/notification/notification_helper.dart:137`) ถูก
เรียกเฉพาะตอนแอป**เปิดอยู่หรือเพิ่งกลับมา foreground** (`RootShell.initState`
+ `didChangeAppLifecycleState` ใน `main.dart`) เท่านั้น — โค้ดมีคอมเมนต์
ระบุข้อจำกัดนี้ไว้ตรงๆ ที่บรรทัด 130-136 ของไฟล์เดียวกันด้วยซ้ำ

**เหตุผลทางเทคนิค:** การรับประกันว่าแจ้งเตือนจะขึ้นแม้แอปปิดสนิทอยู่ทั้งวัน
ต้องมี server-side push (Firebase Cloud Messaging หรือเทียบเท่า) ที่ backend
ต้อง trigger เองตามเวลา ไม่ใช่ local notification ที่ตั้งจากฝั่ง client —
งานนี้อยู่นอกขอบเขตของ prompt ที่ให้ไว้ (ซึ่งระบุชัดว่าให้ใช้
`flutter_local_notifications` เท่านั้น ไม่เพิ่ม dependency ใหม่ที่ไม่จำเป็น)
และต้องตั้งค่า Firebase project + server credentials เพิ่ม ซึ่งเป็นงานแยก
ที่ใหญ่กว่าการแจ้งเตือนในแอปมาก

**ผลกระทบจริง:** ผู้ใช้ที่เปิดแอปอย่างน้อย 1 ครั้งต่อวัน (ปกติของพฤติกรรม
แอปติดตามมื้ออาหาร) จะยังได้รับการเตือนตามปกติ เพราะการตั้งเวลาเกิดขึ้น
ทันทีที่เปิดแอป/กลับมา foreground ก่อนถึงเวลาเตือนจริงเสมอ — ผู้ใช้ที่ไม่
แตะแอปเลยทั้งวันเท่านั้นที่จะไม่ได้รับเตือน (แต่คนกลุ่มนี้ก็ไม่ได้เปิดแอปดู
แจ้งเตือนอยู่แล้วในทางปฏิบัติ)

---

### 8. ทำไมเก็บ `user_consents` แยกจาก `users`

ความยินยอม PDPA ต้องเป็น**หลักฐานย้อนหลังได้** ว่าผู้ใช้ยินยอมนโยบายเวอร์ชัน
ไหนตอนไหน ไม่ใช่แค่สถานะปัจจุบัน — ถ้าเก็บเป็นคอลัมน์ `consented: bool` ใน
`users` ตรงๆ จะตอบไม่ได้เลยว่า "ยินยอมเวอร์ชันไหน" หรือ "ยินยอมกี่ครั้ง
เมื่อไหร่บ้าง" ถ้านโยบายถูกแก้ในอนาคตแล้วต้องพิสูจน์ย้อนหลัง

**กลไกจริง:** `user_consents` (`backend/models.py:323-333`) เป็น
**append-only** — 1 แถวต่อ 1 ครั้งที่กดยินยอม ไม่มี endpoint ไหน
UPDATE/DELETE แถวเดิมเลย (`POST /api/consents`, `backend/api.py:3058-3079`
มีแต่ `db.session.add()`) `GET /api/consents/status`
(`backend/api.py:3035-3055`) หาแถวล่าสุด (`ORDER BY consented_at DESC`)
แล้วเทียบ `policy_version` ของแถวนั้นกับค่าคงที่
`CURRENT_PDPA_POLICY_VERSION` (`backend/config.py:6`) ตรงๆ — ถ้าไม่ตรงกัน
(นโยบายถูก bump เวอร์ชันใหม่หลังจากที่เคยยินยอมไปแล้ว) `consented` จะกลับ
เป็น `false` ทันที บังคับให้ต้องยินยอมนโยบายเวอร์ชันใหม่อีกครั้ง — พฤติกรรม
นี้ทดสอบไว้ใน `backend/tests/test_new_features.py::test_consent_becomes_false_again_after_policy_version_bump`

---

## อ้างอิงเพิ่มเติม

- โครงสร้างโค้ดเต็ม: `ARCHITECTURE.md`
- schema ฐานข้อมูลเต็ม + ER diagram: `DATABASE.md`
- คำนวณมือเทียบ API จริงทุกตัวเลข: `backend/WORKED_EXAMPLE.md`
