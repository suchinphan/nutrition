from pathlib import Path
p=Path(r"C:\Users\USerZ\Downloads\NutritionalHealth\NutritionalHealth\frontend\mobile\lib\page\Choose_food_type_page.dart")
s=p.read_text(encoding='utf-8', errors='replace')
lines=s.splitlines()
stack=[]
pairs={'{':'}','(':')','[':']'}
opens=set(pairs.keys())
closes=set(pairs.values())
for i,line in enumerate(lines, start=1):
    for idx,ch in enumerate(line, start=1):
        if ch in opens:
            stack.append((ch,i,idx,line))
        elif ch in closes:
            if not stack:
                pass
            else:
                last,li,ci,l = stack.pop()
                if pairs[last]!=ch:
                    pass
print('stack remaining count', len(stack))
for item in stack[-10:]:
    ch,li,ci,line = item
    print('open', ch, 'at', li, ci, '->', line.strip())
