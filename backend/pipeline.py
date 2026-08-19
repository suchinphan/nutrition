import pandas as pd
import sqlite3
import os
from datetime import datetime

print("=== DATA CLEANSING PIPELINE ===")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
db_path = os.path.join(BASE_DIR, "pipeline_data.db")

conn = sqlite3.connect(db_path)

# ---------------------------
# LOAD DATA
# ---------------------------
df = pd.read_sql("SELECT * FROM raw_zone", conn)

print("=== DATA BEFORE CLEANING ===")
print("Rows:", len(df))
print("Duplicate rows:", df.duplicated().sum())

# ---------------------------
# CLEAN DATA
# ---------------------------

# 1️⃣ ลบ duplicate
df_clean = df.drop_duplicates().copy()

# 2️⃣ สร้างคอลัมน์ชื่อกลางแบบปลอดภัย
df_clean["item_name"] = None

if "recipe_name" in df_clean.columns:
    df_clean.loc[df_clean["recipe_name"].notna(), "item_name"] = df_clean["recipe_name"]

if "food_name" in df_clean.columns:
    df_clean.loc[df_clean["food_name"].notna(), "item_name"] = df_clean["food_name"]

if "beverage" in df_clean.columns:
    df_clean.loc[df_clean["beverage"].notna(), "item_name"] = df_clean["beverage"]

# 3️⃣ ลบแถวที่ไม่มีชื่อเลย
df_clean = df_clean[df_clean["item_name"].notna()]

# 4️⃣ จัดการตัวเลข
numeric_cols = df_clean.select_dtypes(include="number").columns
df_clean[numeric_cols] = df_clean[numeric_cols].fillna(0)

# ลบค่าติดลบ
for col in numeric_cols:
    df_clean = df_clean[df_clean[col] >= 0]

print("\n=== DATA AFTER CLEANING ===")
print("Rows:", len(df_clean))
print("Duplicate rows:", df_clean.duplicated().sum())

# ---------------------------
# SAVE
# ---------------------------
df_clean.to_sql("cleansing_zone", conn, if_exists="replace", index=False)

# Export CSV
output_folder = os.path.join(BASE_DIR, "data", "presentation")
os.makedirs(output_folder, exist_ok=True)
df_clean.to_csv(os.path.join(output_folder, "cleaned_food.csv"), index=False)

# Metadata
with open(os.path.join(BASE_DIR, "pipeline_metadata.txt"), "a") as f:
    f.write(f"\nRun Date: {datetime.now()}\n")
    f.write(f"Before Rows: {len(df)}\n")
    f.write(f"After Rows: {len(df_clean)}\n")
    f.write(f"Removed Rows: {len(df) - len(df_clean)}\n")

conn.close()

print("\nCleansing pipeline completed successfully!")
