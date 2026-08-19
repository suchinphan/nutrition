import os
import pandas as pd
from api import create_app, db, build_search_name
from models import FoodMenu, FoodCategory
from sqlalchemy import text
from deep_translator import GoogleTranslator
import concurrent.futures

app = create_app()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(BASE_DIR, "data", "menuallcsv", "Food_Nutrition_Dataset.csv")

def safe_float(val):
    try:
        if pd.isna(val) or val == "":
            return None
        return float(val)
    except Exception:
        return None


# Custom dictionary for preferred translations (checked before Google Translate)
CUSTOM_DICT = {
    "Apple, raw": "แอปเปิลสด",
    "Banana chips": "กล้วยทอดกรอบ",
    "Orange juice": "น้ำส้ม",
    "Coffee": "กาแฟ",
    "Tea": "ชา",
    "Milk": "นม"
}


def translate_food_name(name: str) -> str:
    if not name:
        return name
    # Check custom dict (case-insensitive keys)
    for k, v in CUSTOM_DICT.items():
        if name.strip().lower() == k.strip().lower():
            return v
    # Run translator in a separate thread with a short timeout so a
    # slow network call doesn't block the whole import process.
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
            fut = ex.submit(GoogleTranslator(source="en", target="th").translate, name)
            try:
                translated = fut.result(timeout=3)
            except concurrent.futures.TimeoutError:
                return name
    except Exception:
        return name

    if translated is None or str(translated).strip() == "":
        return name
    return translated

def is_real_food(name: str) -> bool:
    name = name.lower().strip()

    # 1. กลุ่มคีย์เวิร์ดของหวาน (Dessert Keywords)
    dessert_keywords = [
        "cake", "candy", "sweet", "dessert", "ice cream",
        "cookie", "pie", "pudding", "syrup", "chocolate",
        "candied", "sugar", "icing", "frosting", "jam",
        "jelly", "caramel", "custard", "donut", "brownie",
        "ขนม", "เค้ก", "บัวลอย", "ทองหยิบ", "ทองหยอด",
        "ฝอยทอง", "โรตี", "เครป", "วาฟเฟิล", "ไอศกรีม", "ข้าวเหนียวมะม่วง"
    ]

    # 2. กลุ่มคีย์เวิร์ดเครื่องดื่มและน้ำผลไม้ (Beverage & Drink Keywords)
    drink_keywords = [
        "juice", "cider", "drink", "beverage", "nectar", 
        "soda", "smoothie", "smoothies", "coffee", "tea", 
        "milkshake", "cocktail", "liquor",
        "น้ำผลไม้", "ไซเดอร์", "เครื่องดื่ม", "น้ำสมุนไพร", "กาแฟ", "ชา"
    ]

    # รวมคีย์เวิร์ดที่ไม่ต้องการทั้งหมด
    excluded_keywords = dessert_keywords + drink_keywords

    # ข้อยกเว้นสำหรับอาหารคาวที่มีชื่อผลไม้ร่วมด้วย (เช่น ไก่ซอสส้ม หรือ สลัด)
    if "chicken" in name or "salsa" in name or "salad" in name:
        return True

    # ถ้าเจอคำในกลุ่มของหวานหรือเครื่องดื่ม ให้รีเทิร์น False (เพื่อข้ามการนำเข้า)
    return not any(k in name for k in excluded_keywords)

def detect_food_type(protein, carbs):
    if protein is None or carbs is None:
        return 4
    if protein > 15 and protein > carbs:
        return 1
    if carbs > 30 and carbs > protein:
        return 3
    return 4

def detect_category_id(food_type_id, protein, calories, category_map):
    if calories is None:
        return 5
    if food_type_id == 1:
        if calories < 300:
            return category_map.get("เมนูโปรตีนแคลอรีต่ำ", 1)
        else:
            return category_map.get("เมนูโปรตีนแคลอรีสูง", 2)
    elif food_type_id == 3:
        if calories < 300:
            return category_map.get("เมนูคาร์โบไฮเดรตแคลอรีต่ำ", 3)
        else:
            return category_map.get("เมนูคาร์โบไฮเดรตแคลอรีสูง", 4)
    return 5

def import_foods():
    with app.app_context():
        # SQL to add the new column for manual DB migration if needed
        print("-- If your DB doesn't have the column yet, run the following SQL:")
        print("ALTER TABLE food_menus ADD COLUMN food_name_th VARCHAR(255) DEFAULT NULL;")

        try:
            print("🧹 กำลังล้างข้อมูลเก่าในตารางอาหารคาว (food_menus)...")
            db.session.execute(text("SET FOREIGN_KEY_CHECKS = 0;"))
            db.session.execute(text("TRUNCATE TABLE food_menus;"))
            db.session.execute(text("SET FOREIGN_KEY_CHECKS = 1;"))
            db.session.commit()
            print("✨ ล้างข้อมูลสำเร็จ เริ่มนำเข้าข้อมูลใหม่...")
        except Exception as e:
            db.session.rollback()
            print(f"❌ ล้างตารางไม่สำเร็จ: {e}")
            return

        if not os.path.exists(CSV_PATH):
            print(f"❌ ไม่พบไฟล์ CSV ที่: {CSV_PATH}")
            return

        df = pd.read_csv(CSV_PATH)
        categories = FoodCategory.query.all()
        category_map = {c.name: c.id for c in categories}

        existing_names = set()
        inserted = 0
        skipped = 0

        for _, row in df.iterrows():
            food_name = str(row.get("food_name", "")).strip()
            if not food_name or food_name.lower() == "nan":
                skipped += 1
                continue

            if not is_real_food(food_name):
                skipped += 1
                continue

            if food_name.lower() in existing_names:
                skipped += 1
                continue

            calories = safe_float(row.get("calories"))
            protein = safe_float(row.get("protein"))
            carbs = safe_float(row.get("carbs"))
            fat = safe_float(row.get("fat"))

            food_type_id = detect_food_type(protein, carbs)
            category_id = detect_category_id(food_type_id, protein, calories, category_map)

            # Translate using centralized translator (custom dict -> Google)
            food_name_th = translate_food_name(food_name)

            food = FoodMenu(
                name=food_name,
                food_name_th=food_name_th,
                food_type_id=food_type_id,
                category_id=category_id,
                calories=calories,
                protein=protein,
                carbs=carbs,
                fat=fat,
                is_dessert=False
            )
            try:
                food.search_name = build_search_name(food_name)
            except Exception:
                food.search_name = food_name.strip().lower()

            db.session.add(food)
            existing_names.add(food_name.lower())
            inserted += 1

        try:
            db.session.commit()
            print(f"✅ บันทึกเมนูอาหารคาวสำเร็จ: {inserted} รายการ (ข้ามไป {skipped} รายการ)")
        except Exception as e:
            db.session.rollback()
            print("❌ เกิดข้อผิดพลาดตอน Commit:", e)

if __name__ == "__main__":
    import_foods()
