#!/usr/bin/env python3
"""
Simple kaggle CSV cleaner: normalize headers, remove duplicate rows, and write cleaned files
to data/kaggle/cleaned/ preserving relative paths.

Usage:
  python tools/clean_kaggle.py

This script is conservative: it only touches CSV files and writes cleaned copies.
"""
import csv
import io
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KAGGLE_DIR = ROOT / 'data' / 'kaggle'
OUT_DIR = KAGGLE_DIR / 'cleaned'
# Also scan these input directories for CSVs (some CSVs live under frontend assets)
INPUT_DIRS = [ROOT / 'data', ROOT / 'frontend' / 'mobile' / 'assets' / 'csv']


def normalize_header(h: str) -> str:
    if h is None:
        return ''
    s = h.strip()
    s = s.replace('\ufeff', '')
    s = s.lower()
    s = s.replace(' ', '_')
    s = s.replace('-', '_')
    s = s.replace('/', '_')
    return s


def clean_csv(inpath: Path, outpath: Path):
    try:
        text = inpath.read_bytes()
        s = text.decode('utf-8-sig')
    except Exception:
        try:
            s = text.decode('latin-1')
        except Exception:
            print('Skipping (unreadable):', inpath)
            return
    rdr = csv.reader(io.StringIO(s))
    rows = list(rdr)
    if not rows:
        return
    header = rows[0]
    norm_header = [normalize_header(h) for h in header]
    seen = set()
    cleaned = [norm_header]
    for r in rows[1:]:
        # pad or truncate to header length to avoid ragged rows
        if len(r) < len(norm_header):
            r = r + [''] * (len(norm_header) - len(r))
        else:
            r = r[:len(norm_header)]
        key = '\t'.join([c.strip() for c in r])
        if key in seen:
            continue
        seen.add(key)
        cleaned.append([c.strip() for c in r])
    outpath.parent.mkdir(parents=True, exist_ok=True)
    with outpath.open('w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        for row in cleaned:
            w.writerow(row)
    print('Wrote:', outpath)


def main():
    # Ensure output dir exists
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    total_found = 0
    total_written = 0
    for input_dir in INPUT_DIRS:
        if not input_dir.exists():
            print('Input folder not found (skipping):', input_dir)
            continue
        any_csv = False
        for root, dirs, files in os.walk(input_dir):
            rootp = Path(root)
            for fn in files:
                if not fn.lower().endswith('.csv'):
                    continue
                any_csv = True
                total_found += 1
                inp = rootp / fn
                # preserve relative path under a subfolder named after the input dir
                try:
                    rel = inp.relative_to(input_dir)
                except Exception:
                    rel = Path(fn)
                outp = OUT_DIR / input_dir.name / rel
                clean_csv(inp, outp)
                total_written += 1
        if not any_csv:
            print('No CSV files found under', input_dir)

    print(f'CSV scan complete. Found: {total_found}, Cleaned written: {total_written} (to {OUT_DIR})')
if __name__ == '__main__':
    main()
