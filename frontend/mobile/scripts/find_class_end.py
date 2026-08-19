path = r"c:\Users\USerZ\Downloads\NutritionalHealth\NutritionalHealth\frontend\mobile\lib\page\Choose_food_type_page.dart"
s = open(path, 'r', encoding='utf-8').read()
cn = 'class _ChooseFoodTypePageState'
start = s.find(cn)
if start<0:
    print('CLASS_NOT_FOUND')
    raise SystemExit(1)
open_idx = s.find('{', start)
if open_idx<0:
    print('OPEN_BRACE_NOT_FOUND')
    raise SystemExit(1)
stack=0
for i in range(open_idx, len(s)):
    if s[i]=='{': stack+=1
    elif s[i]=='}': stack-=1
    if stack==0:
        line = s[:i].count('\n')+1
        print(f'END_IDX:{i} LINE:{line}')
        break
else:
    print('NO_MATCH')
