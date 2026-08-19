print("=== RAW ZONE LOADING ===")

import os
import sqlite3
import pandas as pd
import shutil

# -------------------------
# Paths
# -------------------------

base_dir = os.path.dirname(os.path.abspath(__file__))

raw_dir = os.path.abspath(
    os.path.join(base_dir, "..", "data", "raw")
)

raw_file = os.path.join(raw_dir, "nutrition_raw.csv")

staging_file = os.path.abspath(
    os.path.join(base_dir, "staging_data.csv")
)

db_path = os.path.abspath(
    os.path.join(base_dir, "..", "pipeline_metadata.db")
)

# -------------------------
# Create raw folder if not exists
# -------------------------

os.makedirs(raw_dir, exist_ok=True)

# -------------------------
# If raw file doesn't exist → copy from staging
# -------------------------

if not os.path.exists(raw_file):

    if os.path.exists(staging_file):
        shutil.copy(staging_file, raw_file)
        print("Raw file created from staging_data.csv")
    else:
        raise FileNotFoundError(
            "Neither nutrition_raw.csv nor staging_data.csv found."
        )

# -------------------------
# Load raw data
# -------------------------

df = pd.read_csv(raw_file, dtype=str)

# -------------------------
# Fix duplicate column names
# -------------------------

# Normalize column names (lowercase, strip, replace spaces and remove parens)
cols = (
    pd.Series(df.columns.astype(str))
    .str.strip()
    .str.lower()
    .str.replace(" ", "_")
    .str.replace(r"[()]", "", regex=True)
)

# Make names unique by appending _1, _2... for duplicates
for dup in cols[cols.duplicated()].unique():
    idx = cols[cols == dup].index.tolist()
    for i, j in enumerate(idx):
        if i != 0:
            cols[j] = f"{dup}_{i}"

df.columns = cols

print("Raw shape:", df.shape)
print("Total columns:", len(df.columns))

# -------------------------
# Write to SQLite
# -------------------------

with sqlite3.connect(db_path) as conn:
    df.to_sql(
        "raw_nutrition",
        conn,
        if_exists="replace",
        index=False
    )

print("Raw table created successfully!")
print("=== RAW ZONE COMPLETED ===")
