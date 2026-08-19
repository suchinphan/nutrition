from pathlib import Path

BASE = Path(r"c:/Users/USerZ/Downloads/NutritionalHealth/NutritionalHealth/frontend/mobile/assets/csv/menuallcsv")
files = ['starbucks-menu-nutrition-food.csv','starbucks-menu-nutrition-drinks.csv','starbucks_drinkMenu_expanded.csv']

for fn in files:
    p = BASE / fn
    if not p.exists():
        print(f'{fn} not found')
        continue
    print('Converting', fn)
    data = None
    # try utf-8 first
    try:
        data = p.read_text(encoding='utf-8')
        # quick check for null bytes pattern that suggests utf-16 stored as utf-8
        if '\x00' in data[:1000]:
            raise UnicodeDecodeError('utf-8','',0,1,'likely utf-16')
    except Exception:
        try:
            data = p.read_text(encoding='utf-16')
        except Exception as e:
            print('Failed to read', fn, 'as utf-16:', e)
            continue
    # write back as utf-8
    try:
        p.write_text(data, encoding='utf-8')
        print('Wrote UTF-8', fn)
    except Exception as e:
        print('Failed to write', fn, e)
print('Done')
