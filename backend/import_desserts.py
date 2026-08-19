import os
import pandas as pd
from api import create_app, db, build_search_name
from models import DessertMenu
from deep_translator import GoogleTranslator
import concurrent.futures
from sqlalchemy import text

app = create_app()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(BASE_DIR, "data", "menuallcsv", "Food_Nutrition_Dataset.csv")


DESSERT_KEYWORDS = [
    "cake", "pie", "pudding", "ice cream", "dessert",
    "sweet", "chocolate", "cookie", "brownie",
    "custard", "cupcake", "tart",
    "ขนม", "เค้ก", "บัวลอย", "ทองหยิบ", "ทองหยอด",
    "ฝอยทอง", "โรตี", "เครป", "วาฟเฟิล",
    "ไอศกรีม", "พุดดิ้ง", "ข้าวเหนียวมะม่วง"
]

# Blacklist to exclude savory items that contain ambiguous words
EXCLUDE_KEYWORDS = ["onion", "fries", "raw", "leaves", "tots", "pancake"]


def safe_float(val):
    try:
        if pd.isna(val) or str(val).strip() == "":
            return None
        return float(val)
    except Exception:
        return None


def is_dessert(name: str) -> bool:
    if not name:
        return False
    name = name.lower()
    # Exclude obvious savory keywords first
    if any(ex in name for ex in EXCLUDE_KEYWORDS):
        return False
    # Then check dessert keywords
    return any(k in name for k in DESSERT_KEYWORDS)


def translate_name_en_to_th(name: str) -> str:
    if not name:
        return ""
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
            fut = ex.submit(GoogleTranslator(source="en", target="th").translate, name)
            try:
                return fut.result(timeout=3)
            except concurrent.futures.TimeoutError:
                return ""
    except Exception:
        return ""


def import_desserts():
    with app.app_context():
        print(f"📥 Loading dessert names from: {CSV_PATH}")
        if not os.path.exists(CSV_PATH):
            print(f"❌ CSV file not found at: {CSV_PATH}")
            return

        df = pd.read_csv(CSV_PATH)
        df.columns = df.columns.str.strip()

        name_col = "food_name" if "food_name" in df.columns else "name"

        try:
            existing_desserts = DessertMenu.query.all()
            existing_names = {d.name.lower().strip() for d in existing_desserts if d.name}
            print(f"ℹ️ Found {len(existing_names)} existing records in database.")
        except Exception:
            existing_names = set()

        desserts_to_insert = []
        inserted = 0
        skipped = 0

        for index, row in df.iterrows():
            food_name = str(row.get(name_col, "")).strip()
            category = str(row.get("category", "")).strip()

            if not food_name or food_name.lower() == "nan":
                skipped += 1
                continue

            # Check by name or category, and apply exclude keywords
            if not is_dessert(food_name) and not is_dessert(category):
                skipped += 1
                continue

            if food_name.lower() in existing_names:
                skipped += 1
                continue

            print(f"⏳ Translating: {food_name}")
            dessert_name_th = translate_name_en_to_th(food_name)

            try:
                search_name = build_search_name(food_name)
            except Exception:
                search_name = food_name.lower().strip()

            # name stores the English name from CSV; dessert_name_th stores Thai translation
            dessert_obj = DessertMenu(
                name=food_name,
                dessert_name_th=dessert_name_th,
                calories=safe_float(row.get("calories")),
                protein_g=safe_float(row.get("protein")),
                sugar_g=safe_float(row.get("sugar")),
                fat_g=safe_float(row.get("fat"))
            )
            # attach search_name attribute if model doesn't have a column for it
            try:
                dessert_obj.search_name = search_name
            except Exception:
                pass

            desserts_to_insert.append(dessert_obj)
            existing_names.add(food_name.lower())
            inserted += 1

        # Insert using ORM; fallback to raw SQL if necessary
        try:
            if desserts_to_insert:
                db.session.bulk_save_objects(desserts_to_insert)
                db.session.commit()
                print("⚡ Imported using SQLAlchemy ORM Bulk Save successfully!")
            else:
                print("ℹ️ No new items to insert.")
        except Exception as e:
            db.session.rollback()
            print(f"❌ ORM Failed: {e}. Trying raw SQL fallback...")
            try:
                insert_sql = text(
                    "INSERT INTO dessert_menus (name, dessert_name_th, calories, protein_g, sugar_g, fat_g, search_name) "
                    "VALUES (:name, :dessert_name_th, :calories, :protein_g, :sugar_g, :fat_g, :search_name)"
                )
                for obj in desserts_to_insert:
                    db.session.execute(insert_sql, {
                        'name': obj.name,
                        'dessert_name_th': getattr(obj, 'dessert_name_th', None),
                        'calories': obj.calories,
                        'protein_g': obj.protein_g,
                        'sugar_g': obj.sugar_g,
                        'fat_g': obj.fat_g,
                        'search_name': getattr(obj, 'search_name', None)
                    })
                db.session.commit()
                print("⚡ Fallback Raw SQL completed successfully!")
            except Exception as sql_err:
                db.session.rollback()
                print(f"❌ Critical Error: Both ORM and SQL fallback failed! ({sql_err})")

        print("====================================")
        print(f"✅ Inserted desserts : {inserted}")
        print(f"⏭️ Skipped          : {skipped}")
        print("====================================")


if __name__ == "__main__":
    import_desserts()
