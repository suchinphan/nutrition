ALTER TABLE food_items ADD COLUMN allergens_reviewed TINYINT(1)
  NOT NULL DEFAULT 0;
-- แยกความหมาย "ยังไม่ได้ตรวจสารก่อภูมิแพ้" ออกจาก "ตรวจแล้วว่าไม่มีเลย"
-- (food_allergens ว่างเปล่าสองแบบนี้ความหมายต่างกัน ต้องแยกด้วย column นี้)
-- เพิ่มตอนงานที่ 4 (CSV import) เพราะเมนูที่ import ใหม่ต้องมี default ค่านี้
-- ก่อน — งานที่ 11 (เช็คความสมบูรณ์ของเมนู) จะใช้ column นี้ต่อ ไม่ต้อง
-- ALTER ซ้ำอีกรอบ
