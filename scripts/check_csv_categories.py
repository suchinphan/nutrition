import os
root=os.path.join(os.path.dirname(__file__), '..', 'backend', 'data')
root = os.path.abspath(root)
kw_types={
 'เมนูโปรตีน':['protein','โปรตีน','meat','chicken','pork','fish','egg','tofu','steak','salmon','tuna'],
 'เมนูผักและผลไม้':['vegetable','ผัก','ผลไม้','fruit','salad','vegan'],
 'เมนูคาร์โบไฮเดรต':['carb','rice','noodle','pasta','bread','potato','แป้ง','ข้าว','เส้น'],
 'เครื่องดื่ม':['drink','เครื่องดื่ม','น้ำ','juice','tea','coffee','beverage']
}
kw_goals={'อาหารลดน้ำหนัก':['ลด','weight','loss','ลดน้ำหนัก','slim','low calorie','lowcal','low-cal'],
 'อาหารสร้างกล้ามเนื้อ':['กล้าม','muscle','build muscle','protein','prot','high protein']}
files=[]
for dirpath,dirnames,filenames in os.walk(root):
    import os

    root = os.path.join(os.path.dirname(__file__), '..', 'backend', 'data')
    root = os.path.abspath(root)

    kw_types = {
        'เมนูโปรตีน': ['protein', 'โปรตีน', 'meat', 'chicken', 'pork', 'fish', 'egg', 'tofu', 'steak', 'salmon', 'tuna'],
        'เมนูผักและผลไม้': ['vegetable', 'ผัก', 'ผลไม้', 'fruit', 'salad', 'vegan'],
        'เมนูคาร์โบไฮเดรต': ['carb', 'rice', 'noodle', 'pasta', 'bread', 'potato', 'แป้ง', 'ข้าว', 'เส้น'],
        'เครื่องดื่ม': ['drink', 'เครื่องดื่ม', 'น้ำ', 'juice', 'tea', 'coffee', 'beverage']
    }

    kw_goals = {
        'อาหารลดน้ำหนัก': ['ลด', 'weight', 'loss', 'ลดน้ำหนัก', 'slim', 'low calorie', 'lowcal', 'low-cal'],
        'อาหารสร้างกล้ามเนื้อ': ['กล้าม', 'muscle', 'build muscle', 'protein', 'prot', 'high protein']
    }

    files = []
    for dirpath, dirnames, filenames in os.walk(root):
        for f in filenames:
            if f.lower().endswith('.csv'):
                files.append(os.path.join(dirpath, f))

    print('Found', len(files), 'csv files under', root)

    summary = {}
    for fp in files:
        counts = {'total_rows': 0}
        for k in list(kw_types.keys()) + list(kw_goals.keys()):
            counts[k] = 0
        try:
            with open(fp, encoding='utf-8', errors='ignore') as fh:
                for line in fh:
                    s = line.strip().lower()
                    if not s:
                        continue
                    counts['total_rows'] += 1
                    for t, toks in kw_types.items():
                        for tok in toks:
                            if tok in s:
                                counts[t] += 1
                                break
                    for g, toks in kw_goals.items():
                        for tok in toks:
                            if tok in s:
                                counts[g] += 1
                                break
        except Exception as e:
            counts['error'] = str(e)
        summary[os.path.relpath(fp, root)] = counts

    for k, v in summary.items():
        print('\nFILE:', k)
        print(' rows:', v.get('total_rows', 0))
        for t in kw_types.keys():
            print('  ', t + ':', v.get(t, 0))
        for g in kw_goals.keys():
            print('  ', g + ':', v.get(g, 0))

    agg = {}
    for t in list(kw_types.keys()) + list(kw_goals.keys()):
        agg[t] = 0
    for v in summary.values():
        for t in agg.keys():
            agg[t] += v.get(t, 0)

    print('\nAGGREGATE COUNTS:')
    for k, v in agg.items():
        print(' ', k + ':', v)
