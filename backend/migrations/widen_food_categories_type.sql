ALTER TABLE food_categories MODIFY type VARCHAR(30) NOT NULL DEFAULT 'food';
-- เดิม VARCHAR(10) พอสำหรับ 'food'/'drink'/'dessert' แต่แอดมินเพิ่มหัวข้อใหม่
-- เป็นภาษาไทยเองได้แล้ว (เช่น "ผลไม้") ต้องขยายช่องให้พอ
