CREATE TABLE health_goal_cycles (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  health_goal VARCHAR(20) NOT NULL,
  calories_goal INT,
  period_start DATETIME NOT NULL,
  period_end DATETIME NOT NULL,
  meals_logged INT NOT NULL,
  meals_available INT NOT NULL,
  success_ratio FLOAT NOT NULL,
  is_success TINYINT(1) NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_goal_cycle_user_period (user_id, period_end),
  CONSTRAINT fk_health_goal_cycles_user FOREIGN KEY (user_id)
    REFERENCES users(id) ON DELETE CASCADE
);
-- 1 แถวต่อ 1 รอบเป้าหมายสุขภาพ 7 วันที่จบแล้ว (สรุปครั้งเดียวตอน
-- health_goal_locked_until หมดอายุ ดู api._finalize_expired_goal_cycle) —
-- UNIQUE (user_id, period_end) กันคำนวณซ้ำสองแถวสำหรับรอบเดียวกัน
