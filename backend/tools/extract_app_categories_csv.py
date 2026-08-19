#!/usr/bin/env python3
"""Convert backend/data/extracted_app_categories.json into CSV files.

Produces:
- backend/data/extracted_app_categories.csv (columns: type,category,item)
- backend/data/extracted_app_categories__<type>.csv for each top-level type

Run:
  python tools/extract_app_categories_csv.py
or from repo root:
  python backend/tools/extract_app_categories_csv.py
"""
import json
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / 'data'
IN_FILE = DATA_DIR / 'extracted_app_categories.json'
OUT_FILE = DATA_DIR / 'extracted_app_categories.csv'

SKIP_KEYS = {'histogram_path', 'source_file', 'Histogram Path', 'Caloric Value', 'Protein', 'Fat', 'Dietary Fiber'}

def is_metadata(item: str) -> bool:
    if not item: return True
    low = item.lower()
    # numeric-only entries are likely metadata in this file
    if all((c.isdigit() or c in '.-') for c in low):
        return True
    if low in {k.lower() for k in SKIP_KEYS}:
        return True
    return False

def main():
    if not IN_FILE.exists():
        print(f'Input JSON not found: {IN_FILE}')
        return
    with IN_FILE.open('r', encoding='utf-8') as f:
        data = json.load(f)

    rows = []
    for top_type, categories in data.items():
        if not isinstance(categories, dict):
            continue
        per_type_rows = []
        for cat, items in categories.items():
            if cat in SKIP_KEYS:
                continue
            if not isinstance(items, list):
                continue
            for it in items:
                if not isinstance(it, str):
                    it = str(it)
                if is_metadata(it):
                    continue
                rows.append((top_type, cat, it))
                per_type_rows.append((top_type, cat, it))

        # write per-type CSV
        if per_type_rows:
            safe_name = ''.join(ch if ch.isalnum() else '_' for ch in top_type)[:64]
            out_type = DATA_DIR / f'extracted_app_categories__{safe_name}.csv'
            with out_type.open('w', encoding='utf-8', newline='') as outf:
                writer = csv.writer(outf)
                writer.writerow(['type','category','item'])
                writer.writerows(per_type_rows)
            print(f'Wrote {out_type}')

    # write combined CSV
    if rows:
        with OUT_FILE.open('w', encoding='utf-8', newline='') as outf:
            writer = csv.writer(outf)
            writer.writerow(['type','category','item'])
            writer.writerows(rows)
        print(f'Wrote {OUT_FILE} ({len(rows)} rows)')
    else:
        print('No rows extracted (file may contain only metadata)')

if __name__ == '__main__':
    main()
