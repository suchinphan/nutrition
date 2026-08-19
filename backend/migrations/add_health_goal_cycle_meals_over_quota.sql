ALTER TABLE health_goal_cycles ADD COLUMN meals_over_quota INT NOT NULL DEFAULT 0;
-- จำนวนมื้อในรอบที่กินเกินโควตาต่อมื้อ (calories_goal/3) — เดิม cap นี้
-- บล็อกการบันทึกมื้ออาหารจริง (409 MEAL_CALORIE_CAP_EXCEEDED) ผู้ใช้ขอให้
-- เอาข้อจำกัดออก แล้วเก็บไว้สรุปผลตอนจบรอบเป้าหมายสุขภาพแทน
