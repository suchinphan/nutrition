import os
from remove_bg import remove_bg

imgdir = r'c:\Users\USerZ\Downloads\NutritionalHealth\frontend\mobile\assets\images'
files = os.listdir(imgdir)
# find first jpg with 'ประวัติ' in name
candidates = [f for f in files if 'ประวัติ' in f and f.lower().endswith('.jpg')]
if not candidates:
    print('No history jpg found in', imgdir)
    print('Files:', files)
    raise SystemExit(1)
src = os.path.join(imgdir, candidates[0])
base = os.path.splitext(candidates[0])[0]
out = os.path.join(imgdir, base + '.png')
print('Processing', src, '->', out)
remove_bg(src,out)
print('Done')
