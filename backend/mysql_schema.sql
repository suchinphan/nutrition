-- Bootstrap schema — สร้างตารางทั้งหมดให้ตรงกับ backend/models.py ทุกคอลัมน์
-- (แก้ BUG-003: ไฟล์นี้เคยมีแค่ 3 ตาราง (users/histories/reports) พร้อม
-- คอลัมน์ผิด/เก่า เช่น users.age แทน date_of_birth, reports.ai_reply แทน
-- admin_reply — ทำให้ setup ใหม่ตาม README ได้ schema ที่ใช้แอปจริงไม่ได้เลย)
--
-- ใช้งาน (2 ขั้นตอนตาม README.md):
--   1) mysql -u root -p < create_db_and_user.sql   (สร้าง DB + user ครั้งเดียว)
--   2) mysql -u root -p nutrition_app < mysql_schema.sql   (ไฟล์นี้ — สร้างตาราง)
--
-- ไฟล์นี้ไม่สร้าง DATABASE/USER ซ้ำ (ทำแล้วใน create_db_and_user.sql)
-- ลำดับตารางเรียงตาม FK dependency (ตารางที่ถูกอ้างอิงมาก่อนเสมอ)

USE nutrition_app;

-- ตาราง users
CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(80) NOT NULL UNIQUE,
  email VARCHAR(120),
  password_hash VARCHAR(255) NOT NULL,
  name VARCHAR(60),
  surname VARCHAR(60),
  avatar_url VARCHAR(512),
  gender VARCHAR(10),
  date_of_birth DATE,
  weight FLOAT,
  height FLOAT,
  activity_level VARCHAR(100),
  health_goal VARCHAR(20),
  calories_goal INT,
  health_goal_start_weight FLOAT,
  health_goal_target_weight FLOAT,
  health_goal_target_days INT,
  health_goal_calorie_adjustment INT,
  health_goal_locked_until DATETIME,
  health_goal_started_at DATETIME,
  chronic_diseases JSON,
  food_allergies JSON,
  is_admin TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  password_token VARCHAR(255),
  token_created_at DATETIME,
  reset_token_hash VARCHAR(255),
  reset_token_expires_at DATETIME,
  reset_otp_hash VARCHAR(255),
  reset_otp_expires_at DATETIME,
  reset_otp_attempts INT DEFAULT 0,
  is_deleted TINYINT(1) NOT NULL DEFAULT 0,
  delete_reason TEXT,
  deleted_at DATETIME,
  INDEX ix_users_username (username),
  INDEX ix_users_email (email),
  INDEX ix_users_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง food_categories
CREATE TABLE IF NOT EXISTS food_categories (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  type VARCHAR(30) NOT NULL DEFAULT 'food'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง food_types — หัวข้อทั้งหมด (รวม food/drink/dessert built-in) เก็บ
-- sort_order ไว้ให้ลากเรียงลำดับปนกันได้ — built-in ยัง "แก้ชื่อ/ลบไม่ได้" ตาม
-- PROTECTED_FOOD_TYPES ใน admin_routes.py แต่ลากสลับตำแหน่งได้ปกติ
CREATE TABLE IF NOT EXISTS food_types (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(30) NOT NULL UNIQUE,
  sort_order INT NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT IGNORE INTO food_types (name, sort_order) VALUES ('food', 0), ('drink', 1), ('dessert', 2);

-- ตาราง food_items
CREATE TABLE IF NOT EXISTS food_items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  category_id INT NOT NULL,
  name VARCHAR(255) NOT NULL,
  name_th VARCHAR(255),
  calories FLOAT,
  protein_g FLOAT,
  carbs_g FLOAT,
  fat_g FLOAT,
  fiber_g FLOAT,
  sugar_g FLOAT,
  iron_mg FLOAT,
  vitamin_c_mg FLOAT,
  swap_food_id INT,
  upgrade_tips TEXT,
  image_url VARCHAR(512),
  is_active TINYINT(1) DEFAULT 1,
  allergens_reviewed TINYINT(1) NOT NULL DEFAULT 0,
  INDEX ix_food_items_category_id (category_id),
  INDEX ix_food_items_swap_food_id (swap_food_id),
  FOREIGN KEY (category_id) REFERENCES food_categories(id),
  FOREIGN KEY (swap_food_id) REFERENCES food_items(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง serving_sizes
CREATE TABLE IF NOT EXISTS serving_sizes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  food_item_id INT NOT NULL,
  unit_name VARCHAR(50) NOT NULL,
  unit_name_th VARCHAR(50),
  calories_multiplier FLOAT NOT NULL DEFAULT 1.0,
  grams_approx FLOAT,
  INDEX ix_serving_sizes_food_item_id (food_item_id),
  FOREIGN KEY (food_item_id) REFERENCES food_items(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง allergens
CREATE TABLE IF NOT EXISTS allergens (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL UNIQUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง food_allergens (junction table, composite PK)
CREATE TABLE IF NOT EXISTS food_allergens (
  food_item_id INT NOT NULL,
  allergen_id INT NOT NULL,
  PRIMARY KEY (food_item_id, allergen_id),
  FOREIGN KEY (food_item_id) REFERENCES food_items(id) ON DELETE CASCADE,
  FOREIGN KEY (allergen_id) REFERENCES allergens(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง user_favorite_foods (junction table, composite PK)
CREATE TABLE IF NOT EXISTS user_favorite_foods (
  user_id INT NOT NULL,
  food_item_id INT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, food_item_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (food_item_id) REFERENCES food_items(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง meal_logs (UNIQUE 1 มื้อ/วัน/ประเภทมื้อต่อผู้ใช้)
CREATE TABLE IF NOT EXISTS meal_logs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  log_date DATE NOT NULL,
  meal_type VARCHAR(20) NOT NULL,
  calories_goal INT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX ix_meal_logs_user_id (user_id),
  UNIQUE KEY uq_one_meal_per_day (user_id, log_date, meal_type),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง meal_log_items
CREATE TABLE IF NOT EXISTS meal_log_items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  meal_log_id INT NOT NULL,
  food_item_id INT NOT NULL,
  serving_size_id INT,
  quantity FLOAT NOT NULL DEFAULT 1.0,
  calories_actual FLOAT,
  protein_actual FLOAT,
  carbs_actual FLOAT,
  fat_actual FLOAT,
  is_eaten TINYINT(1) DEFAULT 0,
  eaten_at DATETIME,
  INDEX ix_meal_log_items_meal_log_id (meal_log_id),
  INDEX ix_meal_log_items_food_item_id (food_item_id),
  FOREIGN KEY (meal_log_id) REFERENCES meal_logs(id) ON DELETE CASCADE,
  FOREIGN KEY (food_item_id) REFERENCES food_items(id),
  FOREIGN KEY (serving_size_id) REFERENCES serving_sizes(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง weight_logs (UNIQUE 1 ค่า/วัน/ผู้ใช้ — upsert ฝั่ง backend)
CREATE TABLE IF NOT EXISTS weight_logs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  weight FLOAT NOT NULL,
  logged_at DATE NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX ix_weight_logs_user_id (user_id),
  UNIQUE KEY uq_weight_user_date (user_id, logged_at),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง health_goal_cycles (สรุปผลรอบเป้าหมายสุขภาพ 7 วันที่จบแล้ว — 1 แถว/รอบ)
CREATE TABLE IF NOT EXISTS health_goal_cycles (
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
  weight_start FLOAT NULL,
  weight_end FLOAT NULL,
  weight_delta FLOAT GENERATED ALWAYS AS (weight_end - weight_start) STORED,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  acknowledged_at DATETIME,
  INDEX ix_health_goal_cycles_user_id (user_id),
  UNIQUE KEY uq_goal_cycle_user_period (user_id, period_end),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง reports (ticket system)
CREATE TABLE IF NOT EXISTS reports (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  title VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  admin_reply TEXT,
  replied_at DATETIME,
  user_last_read_message_id INT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX ix_reports_user_id (user_id),
  INDEX ix_reports_created_at (created_at),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง report_messages (thread ข้อความของแต่ละ ticket)
CREATE TABLE IF NOT EXISTS report_messages (
  id INT AUTO_INCREMENT PRIMARY KEY,
  report_id INT NOT NULL,
  sender_type VARCHAR(10) NOT NULL,
  message TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX ix_report_messages_report_id (report_id),
  INDEX ix_report_messages_created_at (created_at),
  FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง submissions (ข้อเสนอเมนูใหม่รอแอดมินตรวจ)
CREATE TABLE IF NOT EXISTS submissions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT,
  anon_id VARCHAR(128) UNIQUE,
  name_th VARCHAR(255),
  name_en VARCHAR(255),
  item_type VARCHAR(10) DEFAULT 'food',
  detail TEXT,
  status VARCHAR(20) DEFAULT 'pending',
  reviewed_by INT,
  review_note TEXT,
  reviewed_at DATETIME,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX ix_submissions_user_id (user_id),
  INDEX ix_submissions_created_at (created_at),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (reviewed_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง profile_audit_log (อ่านอย่างเดียวฝั่งแอดมิน — เขียนอัตโนมัติทุกครั้ง
-- ที่ผู้ใช้แก้โปรไฟล์ตัวเอง ไม่มี ON DELETE CASCADE ตั้งใจ — ดู DATABASE.md)
CREATE TABLE IF NOT EXISTS profile_audit_log (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  field_name VARCHAR(50) NOT NULL,
  old_value TEXT,
  new_value TEXT,
  changed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX ix_profile_audit_log_user_id (user_id),
  INDEX ix_profile_audit_log_changed_at (changed_at),
  FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง user_consents (append-only — PDPA)
CREATE TABLE IF NOT EXISTS user_consents (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  consent_type VARCHAR(50) NOT NULL DEFAULT 'health_data_pdpa',
  policy_version VARCHAR(20) NOT NULL,
  consented_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX ix_user_consents_user_id (user_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ตาราง admin_action_log (ไม่มี ON DELETE CASCADE ตั้งใจ — ดู DATABASE.md)
CREATE TABLE IF NOT EXISTS admin_action_log (
  id INT AUTO_INCREMENT PRIMARY KEY,
  admin_user_id INT NOT NULL,
  action VARCHAR(50) NOT NULL,
  entity_type VARCHAR(50) NOT NULL,
  entity_id INT,
  detail TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (admin_user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- USAGE:
-- 1) mysql -u root -p < create_db_and_user.sql   (สร้าง DB + appuser ครั้งเดียว)
-- 2) mysql -u root -p nutrition_app < mysql_schema.sql   (ไฟล์นี้)
-- 3) ตั้ง env vars แล้วรัน backend ตามปกติ (ดู README.md หัวข้อ backend):
--    $env:MYSQL_USER="appuser"
--    $env:MYSQL_PASS="StrongP@ssw0rd!"
--    $env:MYSQL_DB="nutrition_app"
--    $env:MYSQL_HOST="127.0.0.1"
--    python api.py
