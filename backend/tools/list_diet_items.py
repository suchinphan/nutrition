import csv
from pathlib import Path

keywords = ['ลด', 'weight', 'loss', 'slim', 'diet', 'dietary', 'ลดน้ำหนัก', 'slimfast', 'nesfit']

p = Path(__file__).resolve().parents[1] / 'data' / 'kaggle' / 'cleaned' / 'master_foods.csv'
if not p.exists():
    print('master_foods.csv not found at', p)
    raise SystemExit(1)

seen = set()
items = []

with p.open(encoding='utf-8', errors='ignore') as fh:
    reader = csv.reader(fh)
    header = next(reader, None)
    for row in reader:
        if not row:
            continue
        joined = ' '.join(cell.lower() for cell in row)
        if any(k in joined for k in keywords):
            # pick name: prefer th_name (idx 1), en_name (0), food (8), else first text-like cell
            name = ''
            def safe(i):
                return row[i].strip() if i < len(row) and row[i].strip() else ''
            name = safe(1) or safe(0) or safe(8)
            if not name:
                for cell in row:
                    c = cell.strip()
                    if c and any(ch.isalpha() for ch in c):
                        name = c
                        break
            if not name:
                continue
            if name not in seen:
                seen.add(name)
                items.append(name)

# secondary pass: nutrition-based heuristics (kcal/protein/fiber)
with p.open(encoding='utf-8', errors='ignore') as fh:
    reader = csv.reader(fh)
    header = next(reader, None)
    hdr = [h.lower() for h in (header or [])]
    kcal_idx = next((i for i,h in enumerate(hdr) if 'calor' in h or 'kcal' in h or 'energy' in h), None)
    prot_idx = next((i for i,h in enumerate(hdr) if 'protein' in h or 'prot' in h), None)
    fiber_idx = next((i for i,h in enumerate(hdr) if 'fiber' in h or 'dietary' in h), None)
    for row in reader:
        try:
            kcal = float(row[kcal_idx]) if kcal_idx is not None and kcal_idx < len(row) and row[kcal_idx].strip() else None
        except:
            kcal = None
        try:
            prot = float(row[prot_idx]) if prot_idx is not None and prot_idx < len(row) and row[prot_idx].strip() else None
        except:
            prot = None
        try:
            fiber = float(row[fiber_idx]) if fiber_idx is not None and fiber_idx < len(row) and row[fiber_idx].strip() else None
        except:
            fiber = None
        add = False
        if kcal is not None and kcal > 0 and kcal <= 200:
            add = True
        if fiber is not None and fiber >= 5 and (kcal is None or kcal <= 300):
            add = True
        if add:
            # pick name as before
            def safe(i):
                return row[i].strip() if i < len(row) and row[i].strip() else ''
            name = safe(1) or safe(0) or safe(8)
            if not name:
                for cell in row:
                    c = cell.strip()
                    if c and any(ch.isalpha() for ch in c):
                        name = c
                        break
            if name and name not in seen:
                seen.add(name)
                items.append(name + '  (by nutrition)')

# print summary
print(f'Found {len(items)} matching items (showing up to 200):')
for i, it in enumerate(items[:200], 1):
    print(f'{i}. {it}')
