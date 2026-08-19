CREATE TABLE weight_logs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  weight FLOAT NOT NULL,
  logged_at DATE NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_weight_user_date (user_id, logged_at),
  CONSTRAINT fk_weight_logs_user FOREIGN KEY (user_id)
    REFERENCES users(id) ON DELETE CASCADE
);
-- UNIQUE (user_id, logged_at) = บันทึกได้วันละ 1 ครั้งต่อคน (ระดับ DB
-- เหมือนหลักการเดียวกับ meal_logs)
