-- แก้ BUG-006: add_report_ticket_fields.sql เพิ่มคอลัมน์ `subject` ไว้ แต่
-- models.py (Report class) ใช้ชื่อ `title` มาตั้งแต่ต้น ไม่มี migration ไหน
-- เคยสร้าง `title`/`admin_reply`/`replied_at` เลย (ต่างจาก
-- user_last_read_message_id ที่มี add_reports_read_tracking.sql อยู่แล้ว)
-- ทำให้ deploy ใหม่ที่ไล่รัน migrations/*.sql จากฐานเปล่าจะได้ reports table
-- ที่ INSERT ผ่าน SQLAlchemy ไม่ได้เลย (title เป็น NOT NULL แต่ไม่มีคอลัมน์นี้)
--
-- Migration นี้ purely additive + idempotent: เติมคอลัมน์ที่ขาด และย้ายข้อมูล
-- จาก subject -> title ถ้ามีข้อมูลเก่าอยู่ (เผื่อ DB ไหนเคยรัน
-- add_report_ticket_fields.sql มาก่อนจริง) ไม่ลบ `subject` ทิ้งเผื่อโค้ดอื่น
-- ยังอ่านอยู่ (ตรวจแล้วไม่มีจริงใน api.py/admin_routes.py แต่เก็บไว้ปลอดภัยกว่า)

ALTER TABLE reports
  ADD COLUMN IF NOT EXISTS title VARCHAR(255) NULL,
  ADD COLUMN IF NOT EXISTS admin_reply TEXT NULL,
  ADD COLUMN IF NOT EXISTS replied_at DATETIME NULL;

-- ย้ายข้อมูลจาก subject (ถ้ามีคอลัมน์นี้และมีค่า) เข้า title สำหรับแถวที่
-- title ยังว่างอยู่ — ปลอดภัยรันซ้ำได้ (WHERE title IS NULL กันเขียนทับ)
UPDATE reports SET title = subject WHERE title IS NULL AND subject IS NOT NULL;

-- แถวที่ไม่มีทั้ง title และ subject (เช่น แถวเก่าก่อน add_report_ticket_fields.sql)
-- ใส่ placeholder กัน NOT NULL constraint ด้านล่าง fail — ผู้ใช้เก่าจะเห็นหัวข้อ
-- นี้แทนของจริงที่ไม่เคยมี ไม่ใช่ข้อมูลหาย เพราะไม่เคยมีมาตั้งแต่ต้น
UPDATE reports SET title = 'ไม่มีหัวข้อ' WHERE title IS NULL;

-- ตอนนี้ title มีค่าครบทุกแถวแล้ว ตั้ง NOT NULL ให้ตรงกับ models.py
ALTER TABLE reports MODIFY COLUMN title VARCHAR(255) NOT NULL;
