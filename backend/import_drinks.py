import os
import pandas as pd
from api import create_app, db, build_search_name
from models import DrinkMenu, DrinkType
from sqlalchemy import text
from deep_translator import GoogleTranslator
import concurrent.futures

app = create_app()

BASE_DIR = os.path.dirname(__file__)
CSV_PATH = os.path.join(BASE_DIR, "data", "menuallcsv", "starbucks_drinkMenu_expanded.csv")

def clean_number(val):
    try:
        if pd.isna(val) or val == "":
            return None
        return float(str(val).strip())
    except Exception:
        return None

def clean_percent(val):
    try:
        if pd.isna(val) or val == "":
            return None
        return float(str(val).replace('%', '').strip())
    except Exception:
        return None


# Custom dictionary for preferred translations (checked before Google Translate)
DRINK_CUSTOM_DICT = {
    "coffee": "กาแฟ",
    "latte": "ลาเต้",
    "espresso": "เอสเปรสโซ",
    "apple juice": "น้ำแอปเปิล",
    "orange juice": "น้ำส้ม",
    "milk": "นม",
}


def translate_drink_name(name: str) -> str:
    if not name:
        return name
    # Check custom dict (case-insensitive keys)
    for k, v in DRINK_CUSTOM_DICT.items():
        if name.strip().lower() == k.strip().lower():
            return v
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

def map_drink_type(name: str, category: str):
    name = name.lower()
    category = category.lower()

    # 1) Low / diet indicators -> weight-loss drinks
    if any(k in name for k in ["low", "light", "zero", "diet", "skinny", "sugar-free", "no sugar"]):
        return "เครื่องดื่มลดน้ำหนัก"

    # 2) Tea/juice/smoothie-like categories are treated as healthy drinks
    if any(k in category for k in ["tea", "herbal", "juice", "smoothie"]):
        return "เครื่องดื่มเพื่อสุขภาพ"

    # 3) Coffee/espresso/energy-like categories -> energy drinks
    if any(k in category for k in ["coffee", "espresso", "frappuccino", "cold brew", "shaken"]):
        return "เครื่องดื่มเพิ่มพลังงาน"

    # 4) Fallback: classify as 'เพื่อสุขภาพ' (neutral)
    return "เครื่องดื่มเพื่อสุขภาพ"

def import_drinks():
    with app.app_context():
        try:
            print("🧹 กำลังล้างข้อมูลเก่าในตารางเครื่องดื่มทั้งหมด...")
            db.session.execute(text("SET FOREIGN_KEY_CHECKS = 0;"))
            db.session.execute(text("TRUNCATE TABLE drink_menus;"))
            db.session.execute(text("TRUNCATE TABLE drink_types;"))
            db.session.execute(text("SET FOREIGN_KEY_CHECKS = 1;"))
            db.session.commit()
            print("✨ ล้างตารางฝั่งเครื่องดื่มเรียบร้อยสะอาดหมดจด")
        except Exception as e:
            db.session.rollback()
            print(f"❌ ล้างตารางเครื่องดื่มไม่สำเร็จ: {e}")
            return

        if not os.path.exists(CSV_PATH):
            print(f"❌ ไม่พบไฟล์เครื่องดื่มที่: {CSV_PATH}")
            return

        df = pd.read_csv(CSV_PATH)
        # strip stray whitespace around column names (the CSV has inconsistent headers)
        df.columns = df.columns.str.strip()
        drink_types = {}
        existing_names = set()
        inserted = 0
        skipped = 0

        for _, row in df.iterrows():
            name = str(row.get("Beverage", "")).strip()
            category = str(row.get("Beverage_category", "")).strip()
            prep = str(row.get("Beverage_prep", "")).strip()

            if prep and prep.lower() != "nan":
                name = f"{name} ({prep})"

            if not name or name.lower() == "nan":
                skipped += 1
                continue

            if name.lower() in existing_names:
                skipped += 1
                continue

            drink_type_name = map_drink_type(name, category)

            if drink_type_name not in drink_types:
                drink_type = DrinkType.query.filter_by(name=drink_type_name).first()
                if not drink_type:
                    drink_type = DrinkType(name=drink_type_name)
                    db.session.add(drink_type)
                    db.session.flush()
                drink_types[drink_type_name] = drink_type
            else:
                drink_type = drink_types[drink_type_name]

            drink_data = {
                'name': name,
                'drink_type_id': drink_type.id,
                'calories': clean_number(row.get("Calories")),
                'sugar_g': clean_number(row.get("Sugars (g)")),
                'protein_g': clean_number(row.get("Protein (g)")),
                'iron': clean_percent(row.get("Iron (% DV)")),
                'vitamin_c': clean_percent(row.get("Vitamin C (% DV)")),
            }
            if hasattr(DrinkMenu, 'drink_name_th'):
                drink_data['drink_name_th'] = translate_drink_name(name)
            drink = DrinkMenu(**drink_data)
            try:
                drink.search_name = build_search_name(name)
            except Exception:
                drink.search_name = name.strip().lower()

            db.session.add(drink)
            existing_names.add(name.lower())
            inserted += 1

        try:
            db.session.commit()
            print(f"✅ บันทึกเมนูเครื่องดื่มสำเร็จ: {inserted} รายการ")
        except Exception as e:
            db.session.rollback()
            print("❌ เกิดข้อผิดพลาดตอนบันทึกเครื่องดื่ม:", e)

if __name__ == "__main__":
    import_drinks()
