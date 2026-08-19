import os
import pandas as pd
import sqlite3
from datetime import datetime

print("=== DATA COLLECTION STEP ===")
print("SCRIPT VERSION: FIXED LATIN-1")

base_dir = os.path.dirname(os.path.abspath(__file__))
raw_folder = os.path.join(base_dir, "..", "data", "menuallcsv")
db_path = os.path.join(base_dir, "pipeline_metadata.db")

try:
    files = os.listdir(raw_folder)

    total_rows = 0
    total_columns = 0
    file_count = 0

    for file in files:
        if file.lower().endswith(".csv"):
            path = os.path.join(raw_folder, file)
            print("Reading:", file)

            df = pd.read_csv(
                path,
                encoding="latin-1",
                engine="python",
                on_bad_lines="skip"
            )

            file_count += 1
            total_rows += df.shape[0]
            total_columns = df.shape[1]

    run_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

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

    cursor.execute("""
        INSERT INTO pipeline_metadata
        (step_name, file_count, row_count, column_count, run_time, status)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (
        "Collection",
        file_count,
        total_rows,
        total_columns,
        run_time,
        "SUCCESS"
    ))

    conn.commit()
    conn.close()

    print("SUCCESS ✅")

except Exception as e:
    print("Collection Failed:", e)
