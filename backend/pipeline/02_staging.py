import os
import pandas as pd
import sqlite3
from datetime import datetime

# ==============================
# 1. หา path ปัจจุบัน
# ==============================
base_dir = os.path.dirname(os.path.abspath(__file__))

# backend\data\menuallcsv
raw_folder = os.path.abspath(
    os.path.join(base_dir, "..", "data", "menuallcsv")
)

# output ไฟล์ staging
output_file = os.path.join(base_dir, "staging_data.csv")

# database metadata
db_path = os.path.abspath(
    os.path.join(base_dir, "..", "pipeline_metadata.db")
)

print("=== DATA STAGING STEP ===")
print("Base dir:", base_dir)
print("Looking for folder at:", raw_folder)
print("Database path:", db_path)

try:
    # ==============================
    # 2. เช็คโฟลเดอร์
    # ==============================
    if not os.path.exists(raw_folder):
        raise FileNotFoundError(f"Folder not found: {raw_folder}")

    csv_files = [f for f in os.listdir(raw_folder) if f.endswith(".csv")]

    if len(csv_files) == 0:
        raise ValueError("No CSV files found in folder.")

    print(f"Found {len(csv_files)} CSV files")

    all_data = []

    # ==============================
    # 3. อ่านไฟล์ CSV (รองรับหลาย encoding)
    # ==============================
    for file in csv_files:
        path = os.path.join(raw_folder, file)
        print("Reading:", file)

        try:
            df = pd.read_csv(path, encoding="utf-8")
        except UnicodeDecodeError:
            try:
                df = pd.read_csv(path, encoding="utf-16")
            except UnicodeDecodeError:
                df = pd.read_csv(path, encoding="latin1")

        df = df.drop_duplicates()
        df = df.dropna()

        all_data.append(df)

    # ==============================
    # 4. รวมข้อมูล
    # ==============================
    if not all_data:
        raise ValueError("No valid data to concatenate.")

    final_df = pd.concat(all_data, ignore_index=True)

    final_df.to_csv(output_file, index=False)

    print("Saved staging file at:", output_file)

    # ==============================
    # 5. บันทึก Metadata ลง SQLite
    # ==============================
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

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
        "Staging",
        len(csv_files),
        final_df.shape[0],
        final_df.shape[1],
        run_time,
        "SUCCESS"
    ))

    conn.commit()
    conn.close()

    print("Staging completed successfully!")
    print("Total rows after cleaning:", final_df.shape[0])
    print("Total columns:", final_df.shape[1])

except Exception as e:
    print("Staging Failed:", e)
