import os
import sqlite3
import pandas as pd
from datetime import datetime

base_dir = os.path.dirname(os.path.abspath(__file__))

# Resolve files relative to this script so `run_pipeline.py` can be run from backend/
input_file = os.path.join(base_dir, "cleansed_data.csv")
output_folder = os.path.join(base_dir, "presentation_zone")
output_file = os.path.join(output_folder, "final_dashboard_food.csv")

try:
    if not os.path.exists(input_file):
        raise FileNotFoundError("Cleansed file not found")

    # สร้างโฟลเดอร์ถ้ายังไม่มี
    os.makedirs(output_folder, exist_ok=True)

    df = pd.read_csv(input_file)

    # ตัวอย่าง presentation logic
    df = df.head(100)

    df.to_csv(output_file, index=False)

    row_count = df.shape[0]
    column_count = df.shape[1]
    run_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    status = "SUCCESS"

    # Prefer repo-level pipeline_metadata.db
    db_path = os.path.abspath(os.path.join(base_dir, "..", "pipeline_metadata.db"))
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("""
        INSERT INTO pipeline_metadata
        (step_name, file_count, row_count, column_count, run_time, status)
        VALUES (?, ?, ?, ?, ?, ?)
    """, ("Presentation", 1, row_count, column_count, run_time, status))

    conn.commit()
    conn.close()

    print("Presentation completed!")
    print("File saved to presentation_zone")
    print("Metadata inserted successfully")

except Exception as e:
    print("Presentation failed:", e)