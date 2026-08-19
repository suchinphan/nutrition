-- เพิ่มคอลัมน์ image_url ลงในตาราง dessert_menus
ALTER TABLE dessert_menus ADD COLUMN image_url VARCHAR(500) NULL DEFAULT NULL;
