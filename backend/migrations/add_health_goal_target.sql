ALTER TABLE users ADD COLUMN health_goal_target_weight FLOAT NULL;
ALTER TABLE users ADD COLUMN health_goal_target_days INT NULL;
-- น้ำหนักเป้าหมาย/จำนวนวันที่กรอกในกล่อง "วางแผนพลังงาน" ตอนบันทึก
-- health_goal ล่าสุด — เดิมไม่เก็บเลย มีแต่ผลลัพธ์ (calories_goal) พอ
-- รีเฟรช/เปิดแอปใหม่ ช่องกรอกในกล่องวางแผนพลังงานเลยว่างเปล่า ทั้งที่
-- เพิ่งกรอก+คำนวณ+บันทึกไปแล้ว (ผู้ใช้รายงานจริง)
