print("RUNNING QUALITY BEFORE CHECK")
print("FILE PATH:", __file__)

import os
import pandas as pd
import sqlite3
from datetime import datetime

print("=== DATA QUALITY ASSESSMENT (BEFORE CLEANSING) ===")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

INPUT_FILE = os.path.join(BASE_DIR, "staging_data.csv")
DB_PATH = os.path.join(BASE_DIR, "pipeline_metadata.db")

try:
    # -----------------------------------
    # 1. Check staging file
    # -----------------------------------
    if not os.path.exists(INPUT_FILE):
        raise FileNotFoundError("staging_data.csv not found. Run 02_staging.py first.")

    print("Reading staging file:", INPUT_FILE)

    df = pd.read_csv(INPUT_FILE, encoding="latin-1")

    total_rows, total_columns = df.shape

    # -----------------------------------
    # 2. Data Quality Metrics
    # -----------------------------------

    # Missing values
    missing_count = df.isnull().sum().sum()
    total_cells = total_rows * total_columns
    missing_percent = (missing_count / total_cells) * 100 if total_cells > 0 else 0

    # Duplicate rows
    duplicate_count = df.duplicated().sum()
    duplicate_percent = (duplicate_count / total_rows) * 100 if total_rows > 0 else 0

    run_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # -----------------------------------
    # 3. Save Metadata
    # -----------------------------------
    with sqlite3.connect(DB_PATH) as conn:
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

        cursor.execute("""
            INSERT INTO pipeline_metadata
            (step_name, file_count, row_count, column_count, run_time, status)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (
            "Quality_Before",
            1,
            total_rows,
            total_columns,
            run_time,
            f"Missing:{missing_percent:.2f}% | Duplicate:{duplicate_percent:.2f}%"
        ))

        conn.commit()

    # -----------------------------------
    # 4. Print Summary
    # -----------------------------------
    print("\n========== QUALITY SUMMARY (BEFORE) ==========")
    print("Total Rows:", total_rows)
    print("Total Columns:", total_columns)
    print("Missing Values:", missing_count)
    print("Missing %:", round(missing_percent, 2))
    print("Duplicate Rows:", duplicate_count)
    print("Duplicate %:", round(duplicate_percent, 2))
    print("Status: SUCCESS ✅")
    print("=============================================")

except Exception as e:
    import traceback
    traceback.print_exc()
