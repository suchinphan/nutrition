#!/usr/bin/env python3
"""
Merge cleaned food CSVs into a single master CSV and copy it to frontend assets.

Usage:
  python tools/merge_foods.py

Output:
  - backend/data/kaggle/cleaned/master_foods.csv
  - copied to frontend/mobile/assets/csv/master_foods.csv (creates folder if needed)
"""
import csv
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
CLEANED_DIR = ROOT / 'data' / 'kaggle' / 'cleaned'
OUT_MASTER = CLEANED_DIR / 'master_foods.csv'
FRONTEND_ASSETS = ROOT / 'frontend' / 'mobile' / 'assets' / 'csv'


def collect_csv_paths(base: Path):
    paths = []
    if not base.exists():
        return paths
    for p in base.rglob('*.csv'):
        # skip the master if present
        if p.name == 'master_foods.csv':
            continue
        paths.append(p)
    return paths


def read_csv_rows(path: Path):
    text = path.read_text(encoding='utf-8', errors='replace')
    reader = csv.DictReader(text.splitlines())
    rows = list(reader)
    headers = reader.fieldnames or []
    return headers, rows


def main():
    csvs = collect_csv_paths(CLEANED_DIR)
    if not csvs:
        print('No cleaned CSVs found under', CLEANED_DIR)
        sys.exit(1)
    all_headers = []
    rows_acc = []
    for p in csvs:
        try:
            headers, rows = read_csv_rows(p)
        except Exception as e:
            print('Failed to read', p, e)
            continue
        # normalize header order: keep seen headers and append new ones
        for h in headers:
            if h not in all_headers:
                all_headers.append(h)
        for r in rows:
            # annotate source file to help debugging
            r['_source_file'] = str(p.relative_to(CLEANED_DIR))
            rows_acc.append(r)
    # ensure _source_file is in headers
    if '_source_file' not in all_headers:
        all_headers.append('_source_file')
    # write master
    OUT_MASTER.parent.mkdir(parents=True, exist_ok=True)
    with OUT_MASTER.open('w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=all_headers)
        w.writeheader()
        for r in rows_acc:
            # ensure all keys exist
            out = {k: (r.get(k) or '').strip() for k in all_headers}
            w.writerow(out)
    print('Wrote master:', OUT_MASTER)
    # copy to frontend assets
    try:
        FRONTEND_ASSETS.mkdir(parents=True, exist_ok=True)
        dest = FRONTEND_ASSETS / OUT_MASTER.name
        dest.write_bytes(OUT_MASTER.read_bytes())
        print('Copied master to:', dest)
    except Exception as e:
        print('Failed to copy to frontend assets:', e)

if __name__ == '__main__':
    main()
