CREATE TABLE IF NOT EXISTS food_types (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(30) NOT NULL UNIQUE,
  sort_order INT NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
-- หัวข้อ built-in (food/drink/dessert) ไม่มีแถวที่นี่ — คงที่ในโค้ดเสมอ เก็บ
-- เฉพาะหัวข้อที่แอดมินเพิ่มเอง เพื่อให้มี sort_order ลากเรียงลำดับได้ และสร้าง
-- หัวข้อว่างได้โดยยังไม่ต้องมีหมวดหมู่ย่อย (ดู admin_routes.py create_food_type)
