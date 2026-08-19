import os
import csv
import re

BASE = os.path.join(os.path.dirname(__file__), '..', 'backend', 'data')
BASE = os.path.normpath(BASE)

PRIMARY = ['เมนูโปรตีน','เมนูผักและผลไม้','เมนูคาร์โบไฮเดรต','เครื่องดื่ม']

# app categories per primary type
PRIMARY_APP_MAP = {
    'เมนูโปรตีน': ['อาหารครบ 5 หมู่','อาหารลดน้ำหนัก','อาหารสร้างกล้ามเนื้อ'],
    'เมนูผักและผลไม้': ['อาหารครบ 5 หมู่','อาหารลดน้ำหนัก','อาหารบำรุงสุขภาพ/เสริมภูมิคุ้มกัน'],
    'เมนูคาร์โบไฮเดรต': ['อาหารครบ 5 หมู่','อาหารลดน้ำหนัก','อาหารให้พลังงานสูง / เสริมพลังงาน'],
    'เครื่องดื่ม': ['เครื่องดื่มเพื่อสุขภาพ','เครื่องดื่มลดน้ำหนัก','เครื่องดื่มบำรุงร่างกาย / เพิ่มพลังงาน']
}

protein_keywords = ['protein','โปรตีน','meat','chicken','fish','egg','tofu','tempeh','steak','salmon','tuna','shrimp','beef','pork']
weight_hints = ['low','ลด','salad','grill','grilled','steamed','baked','นึ่ง','ต้ม','ย่าง','no oil','no sugar','ผัก']
muscle_hints = ['กล้าม','muscle','high protein','protein rich','สร้างกล้าม','เวย์']
health_hints = ['health','healthy','สุขภาพ','immune','ภูมิคุ้มกัน','บำรุง']
energy_hints = ['energy','พลังงาน','ให้พลังงาน','high energy','ให้พลังงานสูง']

seen = set()
items_by_primary = {p: set() for p in PRIMARY}
name_to_combined = {}

# helper to read CSV robustly
def read_rows(path):
    rows = []
    try:
        with open(path, newline='', encoding='utf-8') as f:
            for r in csv.reader(f):
                if not any(cell.strip() for cell in r):
                    continue
                rows.append([cell.strip() for cell in r])
    except Exception:
        try:
            with open(path, newline='', encoding='latin-1') as f:
                for r in csv.reader(f):
                    if not any(cell.strip() for cell in r):
                        continue
                    rows.append([cell.strip() for cell in r])
        except Exception:
            return []
    return rows

# find item column heuristically
def pick_item_col(rows):
    if not rows: return None
    # if header-like first row contains name-like tokens, pick index
    first = rows[0]
    name_idx = None
    for i,cell in enumerate(first):
        low = cell.lower()
        if any(k in low for k in ['name','th_name','en_name','food','ชื่อ','อาหาร']):
            name_idx = i
            break
    if name_idx is not None:
        return name_idx, True
    # otherwise score columns by alphabetic content
    col_count = max(len(r) for r in rows)
    scores = [0]*col_count
    letter_re = re.compile(r'[A-Za-z\u0E00-\u0E7F]')
    sample = rows[:min(50,len(rows))]
    for r in sample:
        for c in range(len(r)):
            if letter_re.search(r[c]):
                scores[c]+=1
    best = max(range(len(scores)), key=lambda i: scores[i])
    return best, False

# iterate csv files and classify items by primary type
for root,dirs,files in os.walk(BASE):
    for fn in files:
        if not fn.lower().endswith('.csv'): continue
        path = os.path.join(root,fn)
        rows = read_rows(path)
        if not rows: continue
        item_col, has_header = pick_item_col(rows)
        start = 1 if has_header else 0
        for r in rows[start:]:
            if item_col >= len(r): continue
            name = r[item_col].strip()
            if not name: continue
            # filter out numeric-only or file-path-like entries
            lowname = name.lower()
            if re.fullmatch(r'\d+', lowname):
                continue
            if '/' in name or '\\' in name or re.search(r'\.(png|jpg|jpeg|gif|svg|pdf)$', lowname):
                continue
            # dedupe by exact name
            if name in seen: continue
            seen.add(name)
            combined = ' '.join(r).lower()
            # decide primary type by heuristics
            def pick_primary(combined, name):
                lower = (combined + ' ' + name).lower()
                if any(tok in lower for tok in ['ผัก','ผลไม้','vegetable','fruit','salad']):
                    return 'เมนูผักและผลไม้'
                if any(tok in lower for tok in ['ข้าว','คาร์บ','carb','noodle','rice','bread','แป้ง','pasta','potato']):
                    return 'เมนูคาร์โบไฮเดรต'
                if any(tok in lower for tok in ['น้ำ','เครื่องดื่ม','drink','juice','tea','กาแฟ','coffee','smoothie','beverage']):
                    return 'เครื่องดื่ม'
                return 'เมนูโปรตีน'

            primary = pick_primary(combined, name)
            items_by_primary[primary].add(name)
            name_to_combined[name] = combined

# Now build mapping per primary type -> its app categories
final = {p: {cat: [] for cat in PRIMARY_APP_MAP[p]} for p in PRIMARY}
MAX_PER = 200

for p in PRIMARY:
    pool = sorted(items_by_primary[p])
    used_local = set()
    for name in pool:
        lower = name.lower()
        combined_lower = name_to_combined.get(name, lower)
        assigned = False
        # weight hint
        if any(h in lower for h in weight_hints):
            target = PRIMARY_APP_MAP[p][1]  # second slot is weight-loss for all
            final[p][target].append(name)
            used_local.add(name)
            continue
        # muscle hint (only meaningful for protein)
        if p == 'เมนูโปรตีน' and any(h in lower for h in muscle_hints):
            target = PRIMARY_APP_MAP[p][2]
            final[p][target].append(name)
            used_local.add(name)
            continue
        # health hint
        if any(h in combined_lower for h in health_hints):
            # pick appropriate health-like category (third slot for veg, first for drinks)
            if p == 'เมนูผักและผลไม้':
                final[p][PRIMARY_APP_MAP[p][2]].append(name)
                used_local.add(name)
                continue
            if p == 'เครื่องดื่ม':
                final[p][PRIMARY_APP_MAP[p][0]].append(name)
                used_local.add(name)
                continue
        # energy hint for carbs or drinks
        if any(h in combined_lower for h in energy_hints):
            if p == 'เมนูคาร์โบไฮเดรต':
                final[p][PRIMARY_APP_MAP[p][2]].append(name)
                used_local.add(name)
                continue
            if p == 'เครื่องดื่ม':
                final[p][PRIMARY_APP_MAP[p][2]].append(name)
                used_local.add(name)
                continue

    # remaining -> fallback distribution to balance categories and avoid huge 'ครบ 5 หมู่'
    remaining = [n for n in pool if n not in used_local]
    if p == 'เมนูโปรตีน':
        need_muscle = max(0, 100 - len(final[p][PRIMARY_APP_MAP[p][2]]))
        need_weight = max(0, 100 - len(final[p][PRIMARY_APP_MAP[p][1]]))
        # allocate for muscle
        while need_muscle > 0 and remaining:
            final[p][PRIMARY_APP_MAP[p][2]].append(remaining.pop(0))
            need_muscle -= 1
        # allocate for weight
        while need_weight > 0 and remaining:
            final[p][PRIMARY_APP_MAP[p][1]].append(remaining.pop(0))
            need_weight -= 1
    elif p == 'เมนูผักและผลไม้':
        need_weight = max(0, 60 - len(final[p][PRIMARY_APP_MAP[p][1]]))
        need_health = max(0, 60 - len(final[p][PRIMARY_APP_MAP[p][2]]))
        while need_weight > 0 and remaining:
            final[p][PRIMARY_APP_MAP[p][1]].append(remaining.pop(0))
            need_weight -= 1
        while need_health > 0 and remaining:
            final[p][PRIMARY_APP_MAP[p][2]].append(remaining.pop(0))
            need_health -= 1
    elif p == 'เมนูคาร์โบไฮเดรต':
        need_weight = max(0, 60 - len(final[p][PRIMARY_APP_MAP[p][1]]))
        need_energy = max(0, 60 - len(final[p][PRIMARY_APP_MAP[p][2]]))
        while need_weight > 0 and remaining:
            final[p][PRIMARY_APP_MAP[p][1]].append(remaining.pop(0))
            need_weight -= 1
        while need_energy > 0 and remaining:
            final[p][PRIMARY_APP_MAP[p][2]].append(remaining.pop(0))
            need_energy -= 1
    elif p == 'เครื่องดื่ม':
        need_weight = max(0, 50 - len(final[p][PRIMARY_APP_MAP[p][1]]))
        need_energy = max(0, 50 - len(final[p][PRIMARY_APP_MAP[p][2]]))
        while need_weight > 0 and remaining:
            final[p][PRIMARY_APP_MAP[p][1]].append(remaining.pop(0))
            need_weight -= 1
        while need_energy > 0 and remaining:
            final[p][PRIMARY_APP_MAP[p][2]].append(remaining.pop(0))
            need_energy -= 1

    # default bucket (first slot) gets the remaining up to MAX_PER
    default_cat = PRIMARY_APP_MAP[p][0]
    final[p][default_cat].extend(remaining[:MAX_PER])

# Summarize
print('Summary:')
for p in PRIMARY:
    print(f"{p}:")
    for cat in PRIMARY_APP_MAP[p]:
        print(f"  {cat}: {len(final[p][cat])} items")

# Save
outdir = os.path.join(os.path.dirname(__file__),'..','backend','data')
try:
    import json
    with open(os.path.join(outdir,'extracted_app_categories.json'),'w',encoding='utf-8') as f:
        json.dump(final,f,ensure_ascii=False,indent=2)
    print('\nSaved extracted_app_categories.json')
except Exception as e:
    print('Failed to save JSON:', e)
