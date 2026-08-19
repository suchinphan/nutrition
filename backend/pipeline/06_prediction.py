import os
import sqlite3
import pandas as pd
from datetime import datetime

from sklearn.model_selection import train_test_split
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error, r2_score
from sklearn.impute import SimpleImputer
from sklearn.pipeline import Pipeline
import numpy as np

try:
    print("=== MODEL TRAINING STEP (PREDICTION ZONE) ===")

    base_dir = os.path.dirname(os.path.abspath(__file__))

    # Resolve presentation file relative to this script
    input_file = os.path.join(base_dir, "presentation_zone", "final_dashboard_food.csv")
    output_folder = os.path.join(base_dir, "prediction_zone")
    output_file = os.path.join(output_folder, "model_ready_food.csv")

    # ---------------- Check Input ----------------
    if not os.path.exists(input_file):
        raise FileNotFoundError("Presentation file not found")

    os.makedirs(output_folder, exist_ok=True)

    df = pd.read_csv(input_file)

    print("Total rows:", df.shape[0])
    print("Total columns:", df.shape[1])

    if df.shape[0] < 10:
        raise ValueError("Dataset too small for training")

    # ---------------- Clean Columns ----------------
    # ลบ column ที่ไม่จำเป็น
    if "unnamed_0" in df.columns:
        df = df.drop(columns=["unnamed_0"])

    # บังคับแปลงค่าที่ควรเป็นตัวเลข
    for col in df.columns:
        df[col] = pd.to_numeric(df[col], errors="ignore")

    # ---------------- Select Target ----------------
    if "calories" not in df.columns:
        raise ValueError("Target column 'calories' not found")

    target_column = "calories"

    # แปลง target เป็น numeric
    df[target_column] = pd.to_numeric(df[target_column], errors="coerce")

    # ลบแถวที่ target เป็น NaN
    df = df.dropna(subset=[target_column])

    # ---------------- Select Numeric Features ----------------
    numeric_df = df.select_dtypes(include=[np.number])

    if target_column not in numeric_df.columns:
        raise ValueError("Target column must be numeric")

    X = numeric_df.drop(columns=[target_column])
    y = numeric_df[target_column]

    if X.shape[1] < 1:
        raise ValueError("No numeric features available for training")

    # ลบ feature ที่ค่าคงที่ทั้งคอลัมน์
    X = X.loc[:, X.nunique() > 1]

    print("Numeric features used:", X.shape[1])

    # ---------------- Check NaN ----------------
    print("\nNaN count per column:")
    print(X.isna().sum())

    # ---------------- Split ----------------
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    # ---------------- Build Pipeline ----------------
    pipeline = Pipeline([
        ("imputer", SimpleImputer(strategy="mean")),
        ("model", LinearRegression())
    ])

    # ---------------- Train ----------------
    pipeline.fit(X_train, y_train)

    # ---------------- Predict ----------------
    y_pred = pipeline.predict(X_test)

    # ---------------- Evaluate ----------------
    rmse = np.sqrt(mean_squared_error(y_test, y_pred))
    r2 = r2_score(y_test, y_pred)

    print("\n=== MODEL EVALUATION RESULT ===")
    print("Target column:", target_column)
    print("RMSE:", round(rmse, 4))
    print("R2 Score:", round(r2, 4))

    # ---------------- Save Prediction ----------------
    prediction_df = pd.DataFrame({
        "Actual": y_test.values,
        "Predicted": y_pred
    })

    prediction_df.to_csv(output_file, index=False)

    # ---------------- Save Metadata ----------------
    db_path = os.path.abspath(os.path.join(base_dir, "..", "pipeline_metadata.db"))
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

    file_count = 1
    row_count = df.shape[0]
    column_count = df.shape[1]
    run_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    status = "SUCCESS"

    cursor.execute("""
        INSERT INTO pipeline_metadata
        (step_name, file_count, row_count, column_count, run_time, status)
        VALUES (?, ?, ?, ?, ?, ?)
    """, ("Prediction + Model", file_count, row_count, column_count, run_time, status))

    conn.commit()
    conn.close()

    print("\nPrediction file saved to prediction_zone")
    print("Metadata inserted to DB (Prediction + Model)")
    print("=== PROCESS COMPLETED SUCCESSFULLY ===")

except Exception as e:
    print("Process failed:", e)
