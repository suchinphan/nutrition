import pandas as pd
import sqlite3
import os
from tabulate import tabulate

print("=== PRESENTATION LAYER ===")

# ---------------------------
# CONNECT DATABASE
# ---------------------------

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
db_path = os.path.join(BASE_DIR, "pipeline_data.db")

conn = sqlite3.connect(db_path)

# อ่านข้อมูลจาก cleansing_zone
df = pd.read_sql("SELECT * FROM cleansing_zone", conn)

# ---------------------------
# SAFE NUMERIC CONVERSION
# ---------------------------

def combine_columns(df, cols):
    total = pd.Series(0, index=df.index, dtype=float)
    
    for col in cols:
        if col in df.columns:
            numeric_col = pd.to_numeric(df[col], errors="coerce").fillna(0)
            total += numeric_col
    
    return total

# ---------------------------
# STANDARDIZE NUTRITION
# ---------------------------

df["protein_std"] = combine_columns(df, ["protein_g", "protein", "protein_(g)"])
df["carbs_std"] = combine_columns(df, ["carbs_g", "carbs", "carb._(g)", "total_carbohydrates_(g)"])
df["fat_std"] = combine_columns(df, ["fat_g", "fat", "fat_(g)", "total_fat_(g)"])
df["fiber_std"] = combine_columns(df, ["fiber_g", "fiber_(g)", "dietary_fibre_(g)"])
df["sugar_std"] = combine_columns(df, ["sugar_g", "sugars_(g)"])
df["calories_std"] = combine_columns(df, ["calories"])

# ---------------------------
# SHOW RAW-LIKE TABLE (GRID STYLE)
# ---------------------------

print("\n=== DATA TABLE (Preview 20 rows) ===")

preview_columns = [
    "protein_std",
    "carbs_std",
    "fat_std",
    "fiber_std",
    "sugar_std",
    "calories_std"
]

print(tabulate(df[preview_columns].head(20),
               headers="keys",
               tablefmt="grid",
               showindex=False))

# ---------------------------
# SUMMARY STATISTICS
# ---------------------------

summary = df[preview_columns].describe()

print("\n=== SUMMARY STATISTICS ===")
print(summary)

# ---------------------------
# SAVE OUTPUT
# ---------------------------

output_folder = os.path.join(BASE_DIR, "data", "presentation")
os.makedirs(output_folder, exist_ok=True)

# Save summary
summary.to_csv(os.path.join(output_folder, "nutrition_summary.csv"))

# Save full standardized table
df.to_csv(os.path.join(output_folder, "nutrition_full_table.csv"), index=False)

conn.close()

print("\nPresentation layer completed successfully!")
