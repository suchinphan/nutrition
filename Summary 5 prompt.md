# Summary — สรุปผลการรัน 5 Prompt (Backend/Frontend เพิ่มเติมจากรอบ Design System)

เอกสารนี้สรุปภาพรวมของ 5 prompt ที่รันต่อเนื่องกันในเซสชันนี้ (ต่อจากรอบ
Flutter Design System + Backend Stability + React Admin Dashboard เดิม)
แต่ละหัวข้อระบุ: โจทย์ / สิ่งที่ทำจริง / ไฟล์ที่แก้หรือสร้าง / ผลตรวจสอบ
พร้อมลิงก์ไปเอกสารละเอียดที่สร้างไว้ในแต่ละ prompt

---

## Prompt 1 — หาที่มาของสูตรคำนวณ + รวมจุดคำนวณเดียว (Backend)

**โจทย์:** ทำให้สูตร BMR/TDEE/BMI/แคลอรีทั้งระบบ "อธิบายที่มาได้" — หาสูตรที่
ใช้จริง, เพิ่มสูตร macro 4/4/9, เก็บ macro ที่ทานจริงไม่ใช่แค่แคลอรี, sanity
test TDEE, ทำเอกสารพิสูจน์มือ

**สิ่งที่ทำ:**
1. สำรวจพบว่า `health_calc.py` มีจุดคำนวณกลางอยู่แล้ว (`calc_age`,
   `calc_bmi`, `bmi_status`, `calc_tdee`, `calc_calories_goal`) — สูตร BMR
   คือ Harris-Benedict ต้นฉบับ (1919) พบค่าคงที่ฝั่งหญิงคลาดเคลื่อนจากตำรา
   เล็กน้อย (658.8675 ในโค้ด vs 655.0955 ตามต้นฉบับ) **รายงานไว้ ไม่ได้แก้**
   เพราะไม่มีเอกสารอาจารย์ในรีโปให้เทียบ
2. เพิ่ม `calc_calories_from_macros()` ใน `health_calc.py`
3. Audit `food_items` ทั้งตาราง (3 แถวจริงใน DB) ด้วย
   `tools/sync_food_items_calories.py` แล้ว apply จริง — ปรับ calories ให้
   ตรงสูตร 4/4/9 เป๊ะ (350→333, 430→433, 120 คงเดิม)
4. เพิ่มคอลัมน์ `protein_actual/carbs_actual/fat_actual` ใน `meal_log_items`
   (migration ใน `migrations/add_meal_log_item_macros.sql`, apply บน DB
   จริงแล้ว) แก้ `POST /meal-logs/<id>/items` ให้คำนวณทั้ง 4 ค่าจาก
   multiplier เดียวกัน แก้ `GET /dashboard/summary` ให้คืน
   `eaten_protein/eaten_carbs/eaten_fat`
5. เขียน pytest sanity-check TDEE (ชาย/หญิง office worker) — ผ่านทั้งคู่
   ไม่ต้องปรับสูตร
6. สร้าง `backend/WORKED_EXAMPLE.md` — คำนวณมือครบทุก step เทียบกับ API
   จริง (ผู้ใช้ทดสอบชาย/หญิง 2 คน) ตรงกันทุกตัวเลข

**พบเพิ่ม (นอกขอบเขต ไม่ได้แก้):** ไม่มี column `users.bmi`/
`users.recommended_calories` จริงตามที่โจทย์สมมติ (คำนวณสดตลอด ถือว่าดี
อยู่แล้ว) และ Flutter มีคำนวณ BMR/TDEE/BMI ซ้ำฝั่ง client
(`utils/bmi_calculator.dart`) เพื่อพรีวิวก่อนบันทึก — เกณฑ์ BMI status
ไม่ตรงกับ backend (25/30 vs 23/25)

**ไฟล์ที่แก้/สร้าง:** `backend/health_calc.py`, `backend/api.py`,
`backend/models.py`, `backend/migrations/add_meal_log_item_macros.sql`,
`backend/tools/sync_food_items_calories.py`,
`backend/tests/test_health_calc.py`, `backend/WORKED_EXAMPLE.md`

**ผลตรวจสอบ:** live-test ผ่าน `app.test_client()`/curl กับผู้ใช้ทดสอบจริง
(ลบทิ้งแล้ว), pytest 3 เคสผ่านหมด

---

## Prompt 2 — Automated E2E Test + QA Checklist

**โจทย์:** ทดสอบ flow แบบ end-to-end (สมัคร→login→โปรไฟล์→เลือกอาหาร→
dashboard) ด้วย pytest จริง + เตรียม checklist ให้เดินทดสอบมือบนเครื่องจริง

**สิ่งที่ทำ:**
1. เขียน `backend/tests/test_e2e_flow.py` — ครบ 12 ขั้นตอนตามโจทย์ (register
   → login → update profile → verify age/BMI ตรงกับคำนวณมือ → health-goal →
   food-items ไม่มี null → allergy warning เฉพาะเมนูที่มีกุ้งจริง → บันทึก
   มื้อเช้า → บันทึกซ้ำได้ 409 → mark eaten → dashboard summary ตรงกับที่
   บันทึก → เปลี่ยน weight แล้ว BMI อัปเดตทันทีไม่ค้าง) ใช้
   `app.test_client()` ยิง DB จริง ผ่านผู้ใช้ทดสอบแบบสร้าง-ใช้-ลบทิ้งอัตโนมัติ
   (ไม่มี test-DB/Alembic ให้ hook transaction rollback)
2. สร้าง `QA_CHECKLIST.md` ที่ root — ครบทุกหมวดตามโจทย์ (สมัคร/ล็อกอิน,
   ประวัติ, เลือกอาหาร, ผลลัพธ์, ticket, แอดมิน) พร้อมตาราง log ข้อที่ fail

**ไฟล์ที่แก้/สร้าง:** `backend/tests/test_e2e_flow.py`, `QA_CHECKLIST.md`

**ผลตรวจสอบ:** pytest รวม **4/4 ผ่านทั้งหมด ไม่มีข้อไหน fail** (ไม่มีอะไร
ต้องรายงานสาเหตุ/แก้โค้ดในรอบนี้) ยืนยัน teardown ลบผู้ใช้ทดสอบสะอาดจริง
(รัน 2 รอบ ไม่มี `e2e_%` ค้าง) — `QA_CHECKLIST.md` ยังไม่ได้ติ๊กเพราะต้องเดิน
บนเครื่องจริง ไม่มี emulator ในนี้

---

## Prompt 3 — เอกสารนำเสนอ "โครงสร้าง" (ARCHITECTURE + DATABASE + Q&A)

**โจทย์:** เดินสำรวจโค้ดจริงแล้วอธิบายโครงสร้างทุกโฟลเดอร์ (backend/
frontend mobile/ frontend admin/), อธิบาย schema ทีละตาราง + ER diagram,
เตรียมคำตอบคำถามที่อาจารย์อาจถาม

**สิ่งที่ทำ:**
1. สร้าง `ARCHITECTURE.md` — จัดกลุ่ม endpoint ทั้งหมดใน `api.py`/
   `admin_routes.py`, ตาราง page/service/model ของ Flutter **พร้อมแยกชัดว่า
   หน้าไหน "เข้าถึงได้จริง" กับ "orphaned"** (ตรวจจากการ grep หา `push(...)`
   จริงทุกจุด พบว่าเกินครึ่งของหน้าใน `page/` เข้าไม่ถึงจาก UI ปัจจุบันเลย —
   เป็นซากจาก flow onboarding เก่าที่เข้าถึงได้แค่ผ่าน `MainScreen` ที่ตัวมัน
   เองก็ orphan แล้ว), โครงสร้าง React admin, mermaid flowchart 2 เส้น
2. สร้าง `DATABASE.md` — ครบ 12 ตารางจริง (10 ตามโจทย์ +
   `report_messages`/`profile_audit_log` ที่ตกหล่นจากรายการแต่มีจริงในโค้ด)
   พร้อม ER diagram
3. สร้าง `PRESENTATION_QA.md` — ตอบครบ 6 ข้อ ทุกข้ออ้างไฟล์/บรรทัดจริง
   (ยืนยันว่าไม่มีโค้ด AI/LLM ใดๆ ในระบบสำหรับคำถามเรื่อง AI chat, ยืนยัน
   BMI ใช้เกณฑ์เอเชีย 23/25 จาก `health_calc.py:42-51`)
4. **Follow-up ระหว่างตรวจ:** พบว่า "เปลี่ยนรหัสผ่าน" ไม่มีปุ่มกดถึงได้จาก
   UI ปัจจุบันเลย (จุดเข้าเดิมอยู่ใน `MainScreen` ที่ orphan ไปแล้ว) — เพิ่ม
   ปุ่ม "เปลี่ยนรหัสผ่าน" ใน `ProfilePage` ให้กดถึงได้จริง แล้วอัปเดต
   `ARCHITECTURE.md` ให้ตรงกับโค้ดที่แก้ใหม่

**ไฟล์ที่แก้/สร้าง:** `ARCHITECTURE.md`, `DATABASE.md`,
`PRESENTATION_QA.md`, `frontend/mobile/lib/page/profile_page.dart`

**ผลตรวจสอบ:** ทุก citation (ไฟล์+บรรทัด) ตรวจซ้ำด้วย grep ก่อนส่งมอบ
พบและแก้ citation ผิด 2 จุดระหว่างเขียน (เลขบรรทัดขยับหลังแก้โค้ด Prompt 1,
อ้าง `RegisterLoginPage` ผิดจุดเข้า) — `flutter analyze` 0 issues,
`flutter test` 31/31 ผ่าน หลังเพิ่มปุ่มเปลี่ยนรหัสผ่าน

---

## Prompt 4 — กราฟสัดส่วนเพศบน Admin Dashboard

**โจทย์:** เพิ่ม `GET /admin/dashboard/gender-dist` + donut chart สัดส่วน
เพศ แถวเดียวกับกราฟ health_goal สี ชาย=blue/หญิง=pink/ไม่ระบุ=gray

**สิ่งที่ทำ:**
1. เพิ่ม endpoint ใน `backend/admin/admin_routes.py` — group by
   `users.gender` (`is_deleted=0`) ใช้เกณฑ์ normalize เดียวกับ
   `health_calc.calc_tdee` (`ชาย/male/m`, `หญิง/female/f`) กันมีจุดเช็คเพศ
   ซ้ำกันคนละมาตรฐาน
2. เพิ่ม `getGenderDist()` ใน `api/dashboard.js`
3. เพิ่ม donut chart "สัดส่วนเพศของสมาชิก" ใน `DashboardPage.jsx` — ขยาย
   แถว 3 (Top 10 เมนู / health_goal / เพศ) จาก 2 คอลัมน์เป็น 3 คอลัมน์ สี
   ชาย `#5B8DEF` (สีฟ้าเดียวกับที่ palette เดิมมีอยู่แล้ว), หญิง `#EC4899`,
   ไม่ระบุ `#9CA3AF`

**ไฟล์ที่แก้:** `backend/admin/admin_routes.py`,
`frontend/admin/src/api/dashboard.js`,
`frontend/admin/src/pages/DashboardPage.jsx`

**ผลตรวจสอบ:** live-test endpoint จริงได้ `{male: 3, female: 1,
unspecified: 1}` **ตรงกับ `COUNT` จริงใน DB เป๊ะ** `npm run lint`/
`npm run build` ผ่านสะอาด (เหลือแค่ warning เดิมที่ไม่เกี่ยวกับงานนี้)

---

## Prompt 5 — ตรวจสอบ AI Output/Markdown ดิบที่อาจเหลืออยู่

**โจทย์:** grep ทั้ง repo หา Groq/AI text generation ที่เหลืออยู่ + หาจุด
render string จาก AI ที่อาจมี markdown ดิบปน รายงานผลก่อนแก้ (ไม่ใช่แก้ทันที)

**สิ่งที่ทำ:** grep ครบทั้ง backend/mobile/admin หา `groq`,
`chat_completion`, `ai_reply`, `openai`, `llm`, `markdown` ฯลฯ

**ผลตรวจสอบ — ไม่พบ (ตามที่โจทย์คาดไว้ในกรณี "ไม่เจอ"):**
- ไม่มีโค้ด Groq/OpenAI/LLM integrationใดๆ ในซอร์สจริง (มี
  `google.ai` อยู่ใน `.venv` แต่ไม่ได้อยู่ใน `requirements.txt` และไม่มีไฟล์
  ไหน import — ของค้าง ไม่ได้ต่อกับโปรเจกต์)
- `ai_reply` เจอ 4 จุด แต่เป็นแค่คอมเมนต์บันทึกการลบ (3 จุดฝั่ง Flutter) กับ
  คอลัมน์ในไฟล์ `mysql_schema.sql` ที่**ล้าสมัย ไม่ตรงกับ schema จริงใน
  `models.py`** (bootstrap SQL ที่ไม่ sync มานาน — รายงานไว้ ไม่แก้)
- `ai_random_menu()` (`POST /api/ai/random`) ชื่อมีคำว่า "ai" แต่เนื้อในเป็น
  แค่ `random.choice()` สุ่มเมนูจาก DB ล้วนๆ ไม่ใช่ AI จริง จุดเรียกใช้เดียว
  (`choose_food_type_page.dart`) เป็นหน้า orphan อยู่แล้ว (ดู Prompt 3)
- ระบบแชท/ticket ปัจจุบันมีแค่ `sender_type: 'user'|'admin'` ไม่มี AI/bot
  เหลืออยู่ จึงไม่มีแหล่งข้อความ AI ให้ต้อง render เป็น rich text

**ไฟล์ที่แก้:** ไม่มี (audit-only ตามเงื่อนไขโจทย์)

---

## รวมไฟล์ที่สร้าง/แก้ทั้งหมดใน 5 Prompt นี้

**เอกสารใหม่ (repo root + backend/):**
`backend/WORKED_EXAMPLE.md`, `QA_CHECKLIST.md`, `ARCHITECTURE.md`,
`DATABASE.md`, `PRESENTATION_QA.md`

**Backend โค้ด/schema:** `backend/health_calc.py`, `backend/api.py`,
`backend/models.py`, `backend/admin/admin_routes.py`,
`backend/migrations/add_meal_log_item_macros.sql`,
`backend/tools/sync_food_items_calories.py`,
`backend/tests/test_health_calc.py`, `backend/tests/test_e2e_flow.py`

**Frontend:** `frontend/mobile/lib/page/profile_page.dart`,
`frontend/admin/src/api/dashboard.js`,
`frontend/admin/src/pages/DashboardPage.jsx`

**สถานะทดสอบล่าสุด:** `pytest backend/tests/` 4/4 ผ่าน,
`flutter analyze` 0 issues, `flutter test` 31/31 ผ่าน,
`npm run lint`/`npm run build` (admin) ผ่านสะอาด
