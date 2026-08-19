print("RUNNING VERSION CHECK")
print("FILE PATH:", __file__)

import os
import sqlite3
import pandas
from datetime import datetime

print("========== DATA CLEANSING STEP ==========")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

INPUT_FILE = os.path.join(BASE_DIR, "staging_data.csv")
OUTPUT_FILE = os.path.join(BASE_DIR, "cleansed_data.csv")
DB_PATH = os.path.join(BASE_DIR, "pipeline_metadata.db")

try:
    if not os.path.exists(INPUT_FILE):
        raise FileNotFoundError("staging_data.csv not found.")

    print("Reading staging file:", INPUT_FILE)

    df = pandas.read_csv(INPUT_FILE, encoding="latin-1")

    print("TYPE OF DF:", type(df))

    original_rows, original_cols = df.shape
    print("Original shape:", df.shape)

    # Basic cleaning
    df = df.drop_duplicates()
    df = df.dropna(how="all")

    # Clean column names
    df.columns = (
        df.columns.astype(str)
        .str.strip()
        .str.lower()
        .str.replace(" ", "_", regex=False)
        .str.replace(r"[^\w_]", "", regex=True)
    )

    df = df.loc[:, ~df.columns.duplicated()]

    cleaned_rows, cleaned_cols = df.shape

    if cleaned_rows == 0:
        raise ValueError("All rows removed.")

    # Save CSV
    df.to_csv(OUTPUT_FILE, index=False)
    print("Saved cleansed file:", OUTPUT_FILE)

    # Save metadata
    run_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

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
            "Cleansing",
            1,
            cleaned_rows,
            cleaned_cols,
            run_time,
            "SUCCESS"
        ))

        conn.commit()

    print("\n========== SUMMARY ==========")
    print("Original rows:", original_rows)
    print("Final rows:", cleaned_rows)
    print("Final columns:", cleaned_cols)
    print("Status: SUCCESS ✅")

except Exception as e:
    import traceback
    traceback.print_exc()
