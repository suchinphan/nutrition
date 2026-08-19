print("RUNNING FINAL STABLE TRANSFORMATION FILE")

import os
import sqlite3
import pandas as pd
from datetime import datetime

print("=== DATA TRANSFORMATION STEP ===")

# ==========================================
# 📌 Define Paths (ABSOLUTE SAFE MODE)
# ==========================================
base_dir = os.path.dirname(os.path.abspath(__file__))

input_file = os.path.join(base_dir, "staging_data.csv")
output_file = os.path.join(base_dir, "transformed_data.csv")

# Prefer the project-level pipeline_metadata.db (backend/pipeline_metadata.db)
# but fall back to a local data.db inside the pipeline folder if needed.
parent_db = os.path.abspath(os.path.join(base_dir, "..", "pipeline_metadata.db"))
local_db = os.path.abspath(os.path.join(base_dir, "data.db"))

if os.path.exists(parent_db):
    absolute_db_path = parent_db
elif os.path.exists(local_db):
    absolute_db_path = local_db
else:
    # Default to parent path so the file will be created there on first run
    absolute_db_path = parent_db

print("Base directory:", base_dir)
print("Resolved database path:", absolute_db_path)
print("Database exists:", os.path.exists(absolute_db_path))

try:

    # ===============================
    # 1️⃣ Check file
    # ===============================
    if not os.path.exists(input_file):
        raise FileNotFoundError(f"File not found: {input_file}")

    # ===============================
    # 2️⃣ Read CSV
    # ===============================
    df = pd.read_csv(input_file, dtype=str)
    print("Original shape:", df.shape)

    if df.empty:
        raise ValueError("Input file is empty")

    # ===============================
    # 3️⃣ Clean column names
    # ===============================
    df.columns = (
        df.columns.astype(str)
        .str.lower()
        .str.strip()
        .str.replace(" ", "_")
        .str.replace(r"[()]", "", regex=True)
    )

    # ===============================
    # 4️⃣ Remove duplicate columns (before rename)
    # ===============================
    df = df.loc[:, ~df.columns.duplicated(keep="first")]

    # ===============================
    # 5️⃣ Rename nutrition columns
    # ===============================
    rename_map = {
        "protein": "protein_g",
        "total_carbohydrates_g": "carbs_g",
        "carbohydrates_g": "carbs_g",
        "carb._g": "carbs_g",
        "total_fat_g": "fat_g",
        "dietary_fibre_g": "fiber_g"
    }

    df.rename(columns=rename_map, inplace=True)

    # ===============================
    # 6️⃣ Remove duplicate columns AGAIN (after rename)
    # ===============================
    df = df.loc[:, ~df.columns.duplicated(keep="first")]

    # ===============================
    # 7️⃣ Remove duplicate rows
    # ===============================
    df = df.drop_duplicates()

    # ===============================
    # 8️⃣ Convert numeric safely
    # ===============================
    numeric_cols = ["protein_g", "carbs_g", "fat_g", "fiber_g", "calories"]

    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    print("Transformed shape:", df.shape)

    # ===============================
    # 9️⃣ Save CSV
    # ===============================
    df.to_csv(output_file, index=False)
    print("Saved transformed_data.csv")

    # ===============================
    # 🔟 Insert metadata into DB (SAFE MODE)
    # ===============================

    # 🔥 สร้างไฟล์ DB ถ้าไม่มี
    if not os.path.exists(absolute_db_path):
        print("Database file not found. Creating new database...")

    with sqlite3.connect(absolute_db_path) as conn:
        cursor = conn.cursor()

        # 🔥 บังคับสร้าง table เสมอ
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS pipeline_metadata (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                step_name TEXT,
                file_count INTEGER,
                row_count INTEGER,
                column_count INTEGER,
                run_time TEXT,
                status TEXT
            )
        """)

        run_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        cursor.execute("""
            INSERT INTO pipeline_metadata
            (step_name, file_count, row_count, column_count, run_time, status)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (
            "Transformation",
            1,
            int(df.shape[0]),
            int(df.shape[1]),
            run_time,
            "SUCCESS"
        ))

        conn.commit()

    print("Transformation completed successfully!")

except Exception as e:
    print("Transformation Failed:", str(e))
