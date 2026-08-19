import os,sys
from remove_bg import remove_bg

if len(sys.argv) < 3:
    print('Usage: remove_bg_find.py images_dir target_substring')
    sys.exit(1)
imgdir = sys.argv[1]
target = sys.argv[2]
if not os.path.isdir(imgdir):
    print('Not a dir:', imgdir); sys.exit(2)

# find a file whose name contains target
matches = [f for f in os.listdir(imgdir) if target in f]
if not matches:
    # try normalized matching
    import unicodedata
    target_n = unicodedata.normalize('NFC', target)
    matches = [f for f in os.listdir(imgdir) if target_n in unicodedata.normalize('NFC', f)]

if not matches:
    print('No match found for', target)
    sys.exit(3)
# pick first
src = os.path.join(imgdir, matches[0])
base,ext = os.path.splitext(matches[0])
out = os.path.join(imgdir, base + '.png')
print('Processing', src, '->', out)
remove_bg(src,out)
print('Done')
