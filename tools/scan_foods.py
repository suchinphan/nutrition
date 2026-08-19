import os
import csv
from collections import defaultdict

root = os.path.abspath(os.path.join(os.getcwd(), '..', 'NutritionalHealth'))
# But running from workspace root; adjust
base = os.path.abspath(os.path.join(os.getcwd(), 'backend', 'data'))
if not os.path.isdir(base):
    base = os.path.abspath(os.path.join(os.getcwd(), '..', 'backend', 'data'))

print('Scanning CSVs under', base)

type_tokens = {
    'เมนูโปรตีน': ['protein','โปรตีน','meat','chicken','beef','pork','fish','egg','tofu','tempeh','seafood','shrimp','salmon','tuna','steak','ไก่','ปลา','ไข่','เนื้อ'],
    'เมนูผักและผลไม้': ['vegetable','ผัก','ผลไม้','fruit','salad','vegan','leaf','ผักสด','ผักต้ม'],
    'เมนูคาร์โบไฮเดรต': ['carb','carbo','rice','noodle','pasta','bread','potato','แป้ง','ข้าว','เส้น','ขนมปัง','grain'],
    'เครื่องดื่ม': ['drink','เครื่องดื่ม','น้ำ','beverage','juice','smoothie','tea','coffee','ชา','กาแฟ']
}

goal_tokens = {
    'อาหารลดน้ำหนัก': ['ลด','weight','loss','slim','ลดน้ำหนัก'],
    'อาหารสร้างกล้ามเนื้อ': ['กล้าม','muscle','protein','สร้างกล้าม','build muscle','สร้างกล้ามเนื้อ']
}

matches = {k: set() for k in list(type_tokens.keys()) + list(goal_tokens.keys())}
all_items = set()

for dirpath, dirnames, filenames in os.walk(base):
    for fn in filenames:
        if not fn.lower().endswith('.csv'): continue
        path = os.path.join(dirpath, fn)
        try:
            with open(path, newline='', encoding='utf-8') as f:
                reader = csv.reader(f)
                rows = list(reader)
        except Exception as e:
            print('Failed read', path, e)
            continue
        if not rows:
            continue
        # detect header
        header = rows[0]
        has_header = False
        if any(any(ch.isalpha() for ch in cell) for cell in header):
            has_header = True
        if has_header:
            data = rows[1:]
        else:
            data = rows
        # pick item col heuristics: look for columns with name keywords in header, else pick most text-like
        item_col = None
        if has_header:
            headers = [h.lower() for h in header]
            for i,h in enumerate(headers):
                if any(k in h for k in ['name','food','th_name','en_name','item','title','อาหาร','ชื่อ']):
                    item_col = i
                    break
        if item_col is None:
            # score columns for text content
            col_count = max(len(r) for r in data)
            scores = [0]*col_count
            for r in data[:min(10, len(data))]:
                for c in range(len(r)):
                    if any(ch.isalpha() for ch in r[c]): scores[c]+=1
            item_col = max(range(len(scores)), key=lambda i: scores[i])
        for r in data:
            if item_col >= len(r): continue
            name = r[item_col].strip()
            if not name: continue
            all_items.add(name)
            combined = ' '.join(cell.strip().lower() for cell in r)
            for k,toks in type_tokens.items():
                for t in toks:
                    if t in combined:
                        matches[k].add(name)
                        break
            for k,toks in goal_tokens.items():
                for t in toks:
                    if t in combined:
                        matches[k].add(name)
                        break

print('\nTotals:')
for k in matches:
    print(f"{k}: {len(matches[k])}")

# Show samples
print('\nSamples:')
for k in matches:
    sample = list(matches[k])[:10]
    print(f"{k} sample ({len(sample)}): {sample}")

print('\nTotal unique items scanned:', len(all_items))
