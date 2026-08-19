ALTER TABLE users ADD COLUMN health_goal_started_at DATETIME NULL;
-- จุดเริ่ม "วันที่ 1" ของรอบเป้าหมายสุขภาพ 7 วัน — health_goal_locked_until
-- เปลี่ยนไปปัดเป็น 22:00 ของวันที่ 7 แล้ว (ไม่ใช่ started_at+7 วันตรงๆ) จึง
-- ต้องเก็บจุดเริ่มจริงแยกไว้ ให้ _finalize_expired_goal_cycle คำนวณ
-- period_start ย้อนกลับได้แม่นยำ
