from remove_bg import remove_bg
import os
imgdir = r'c:\Users\USerZ\Downloads\NutritionalHealth\frontend\mobile\assets\images'
src = os.path.join(imgdir, 'รายงานปัญหา.jpg')
out = os.path.join(imgdir, 'รายงานปัญหา.png')
print('Processing', src, '->', out)
remove_bg(src,out)
print('Done')
