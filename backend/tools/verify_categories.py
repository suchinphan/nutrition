import csv
from pathlib import Path
BASE = Path(r"c:/Users/USerZ/Downloads/NutritionalHealth/NutritionalHealth/frontend/mobile/assets/csv/menuallcsv")

# parse Food_Nutrition_Dataset.csv similar to Dart helper

def load_food_categories():
    p = BASE / 'Food_Nutrition_Dataset.csv'
    res = {'protein':[], 'vegetable':[], 'carb':[]}
    if not p.exists():
        return res
    with p.open(encoding='utf-8', errors='replace') as f:
        reader = csv.reader(f)
        rows = list(reader)
        if len(rows)<=1: return res
        header = [h.strip().lower() for h in rows[0]]
        name_idx = next((i for i,h in enumerate(header) if 'food_name' in h or 'name' in h), 0)
        cat_idx = next((i for i,h in enumerate(header) if any(k in h for k in ['category','type','group','หมวด'])), -1)
        seen=set()
        for r in rows[1:]:
            if len(r)<=name_idx: continue
            name = r[name_idx].strip()
            if not name: continue
            key = name.lower()
            if key in seen: continue
            seen.add(key)
            cat_text = (r[cat_idx].lower() if cat_idx>=0 and cat_idx < len(r) else ' '.join([c.lower() for c in r]))
            isProtein = any(t in cat_text for t in ['protein','meat','chicken','fish','egg','pork','beef','seafood','โปรตีน','เนื้อ'])
            isVeg = any(t in cat_text for t in ['vegetable','ผัก','ผลไม้','fruit','salad'])
            isCarb = any(t in cat_text for t in ['carb','carbo','rice','noodle','pasta','bread','แป้ง','ข้าว','เส้น'])
            if isProtein:
                res['protein'].append(name)
                continue
            if isVeg:
                res['vegetable'].append(name)
                continue
            if isCarb:
                res['carb'].append(name)
                continue
            # fallback token scan in row
            combined = ' '.join(r).lower()
            if any(t in combined for t in ['protein','meat','chicken','egg','โปรตีน']):
                res['protein'].append(name); continue
            if any(t in combined for t in ['vegetable','ผัก','ผลไม้','fruit']):
                res['vegetable'].append(name); continue
            if any(t in combined for t in ['rice','noodle','pasta','bread','ข้าว','แป้ง']):
                res['carb'].append(name); continue
    # dedupe preserve order
    for k in res:
        seen2=set(); new=[]
        for n in res[k]:
            kk=n.lower().strip()
            if kk and kk not in seen2:
                seen2.add(kk); new.append(n.strip())
        res[k]=new
    return res


def load_smoothies():
    p = BASE / '000Smoothie-Recipes - Sheet1.csv'
    if not p.exists(): return []
    out=[]
    with p.open(encoding='utf-8', errors='replace') as f:
        reader = csv.reader(f)
        rows=list(reader)
        if not rows: return []
        for r in rows[1:]:
            if not r: continue
            out.append(r[0].strip())
    return list(dict.fromkeys(out))


def load_desserts():
    p = BASE / 'starbucks-menu-nutrition-food.csv'
    if not p.exists(): return []
    out=[]
    with p.open(encoding='utf-8', errors='replace') as f:
        reader = csv.reader(f)
        rows=list(reader)
        if not rows: return []
        for r in rows[1:]:
            if not r: continue
            name = r[0].strip()
            out.append(name)
    # filter dessert tokens
    desserts = [n for n in out if any(t in n.lower() for t in ['cake','pie','dessert','cookie','brownie','muffin','ice cream','scone','tart','pastry','cupcake','fritter','croissant'])]
    return list(dict.fromkeys(desserts))


def load_weightloss_drinks():
    p = BASE / 'starbucks-menu-nutrition-drinks.csv'
    if not p.exists(): return []
    out=[]
    with p.open(encoding='utf-8', errors='replace') as f:
        reader = csv.reader(f)
        rows=list(reader)
        if not rows: return []
        for r in rows[1:]:
            if not r: continue
            name = r[0].strip()
            cal = None
            if len(r)>1:
                try:
                    cal = float(r[1].replace('-',''))
                except:
                    cal=None
            if cal is not None and cal<150:
                out.append(name)
    return list(dict.fromkeys(out))


def load_energy_drinks():
    p = BASE / 'starbucks_drinkMenu_expanded.csv'
    if not p.exists(): return []
    out=[]
    with p.open(encoding='utf-8', errors='replace') as f:
        reader = csv.reader(f)
        rows=list(reader)
        if not rows: return []
        header=[h.strip().lower() for h in rows[0]]
        try:
            name_idx = header.index('beverage')
        except ValueError:
            name_idx = next((i for i,h in enumerate(header) if 'beverage' in h and 'category' not in h),0)
        for r in rows[1:]:
            if len(r)<=name_idx: continue
            name = r[name_idx].strip()
            combined = ' '.join(r).lower()
            if 'coffee' in combined or 'espresso' in combined:
                out.append(name)
    return list(dict.fromkeys(out))

if __name__=='__main__':
    cats = load_food_categories()
    print('protein', len(cats['protein']))
    print('vegetable', len(cats['vegetable']))
    print('carb', len(cats['carb']))
    print('smoothie', len(load_smoothies()))
    print('dessert', len(load_desserts()))
    print('weightloss drinks', len(load_weightloss_drinks()))
    print('energy drinks', len(load_energy_drinks()))
