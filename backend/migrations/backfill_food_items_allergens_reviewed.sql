UPDATE food_items SET allergens_reviewed = 1 WHERE allergens_reviewed = 0;
-- เมนูเก่าที่มีอยู่ก่อนแก้บั๊ก admin_set_food_item_allergens (endpoint ไม่เคย
-- set allergens_reviewed=True เลยสักครั้ง) ค้างเป็น 0 ทั้งหมดถาวร ให้ backfill
-- เป็น "ตรวจแล้ว" ครั้งเดียว ณ ตอนนี้ — จากนี้ไปทุกครั้งที่แอดมินกดบันทึก
-- สารก่อภูมิแพ้ของเมนูใดเมนูหนึ่ง endpoint จะ set ให้ถูกต้องเองแล้ว
