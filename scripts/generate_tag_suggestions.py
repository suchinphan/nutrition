import os
import csv

root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'backend', 'data'))

def pick_name_from_row(row):
    # row is list of cells
    for cell in row:
        s = cell.strip()
        if not s: continue
        # skip numeric-looking cells
        try:
            float(s)
            continue
        except:
            return s
    return ''

def find_numeric_by_header(headers, row, matchers):
    headers = [h.lower() for h in headers]
    for m in matchers:
        for i,h in enumerate(headers):
            if m in h and i < len(row):
                try:
                    return float(row[i].strip())
                except:
                    continue
    return None

suggestions = []
files = []
for dirpath,_,filenames in os.walk(root):
    for f in filenames:
        if f.lower().endswith('.csv'):
            files.append(os.path.join(dirpath,f))

for fp in files:
    rel = os.path.relpath(fp, root).replace('\\','/')
    try:
        with open(fp, encoding='utf-8', errors='ignore') as fh:
            reader = csv.reader(fh)
            rows = list(reader)
            if not rows: continue
            headers = [c.strip() for c in rows[0]]
            # simple heuristic: if header row appears textual (contains letters) assume header
            header_is_real = any(any(ch.isalpha() for ch in h) for h in headers)
            start = 1 if header_is_real else 0
            for r in rows[start: start+2000]:
                if not r: continue
                name = pick_name_from_row(r)
                if not name: continue
                combined = ' '.join(r).lower()
                kcal = find_numeric_by_header(headers, r, ['calor','energy','kcal'])
                prot = find_numeric_by_header(headers, r, ['protein','prot','โปรตีน'])
                fiber = find_numeric_by_header(headers, r, ['fiber','dietary_fiber'])
                tags = []
                reasons = []
                # keyword matches (high confidence)
                if any(k in combined for k in ['ลด','ลดน้ำหนัก','weight','loss','slim','low calorie','low-cal','lowcal']):
                    tags.append('อาหารลดน้ำหนัก'); reasons.append('keyword')
                if any(k in combined for k in ['กล้าม','สร้างกล้าม','muscle','build muscle','high protein']):
                    tags.append('อาหารสร้างกล้ามเนื้อ'); reasons.append('keyword')
                # numeric heuristics
                if kcal is not None and kcal > 0 and kcal <= 220:
                    if 'อาหารลดน้ำหนัก' not in tags:
                        tags.append('อาหารลดน้ำหนัก'); reasons.append('kcal<=220')
                if fiber is not None and fiber >= 4 and (kcal is None or kcal <= 320):
                    if 'อาหารลดน้ำหนัก' not in tags:
                        tags.append('อาหารลดน้ำหนัก'); reasons.append('fiber>=4')
                if prot is not None and prot >= 12:
                    if 'อาหารสร้างกล้ามเนื้อ' not in tags:
                        tags.append('อาหารสร้างกล้ามเนื้อ'); reasons.append('protein>=12')

                if tags:
                    suggestions.append({'source': rel, 'item': name, 'tags': ';'.join(tags), 'reason': ';'.join(reasons)})
    except Exception as e:
        print('skip', rel, e)

out_sug = os.path.join(os.path.dirname(__file__), 'suggested_tags.csv')
with open(out_sug, 'w', encoding='utf-8', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=['source','item','tags','reason'])
    w.writeheader()
    for s in suggestions:
        w.writerow(s)

print('Wrote', len(suggestions), 'suggestions to', out_sug)

# create a small custom_tags.csv in backend/data with the most confident suggestions (keyword-based first)
custom = {}
for s in suggestions:
    conf = 2 if 'keyword' in s['reason'] else 1
    key = (s['item'].strip(), s['source'])
    if key not in custom or custom[key][0] < conf:
        custom[key] = (conf, s['tags'])

custom_path = os.path.join(root, 'custom_tags.csv')
with open(custom_path, 'w', encoding='utf-8', newline='') as fh:
    w = csv.writer(fh)
    w.writerow(['source_file','item','tags'])
    for (item, src), (conf, tags) in list(custom.items())[:1000]:
        w.writerow([src, item, tags])

print('Wrote custom tags to', custom_path)
