p='frontend/mobile/lib/page/Choose_food_type_page.dart'
s=open(p,encoding='utf-8').read()
# naive: remove // comments and /* */ and strings to avoid false matches
import re
# remove block comments
s=re.sub(r'/\*.*?\*/','',s,flags=re.S)
# remove line comments
s=re.sub(r'//.*?\n','\n',s)
# remove string literals (single, double, triple)
s=re.sub(r"\'\'\'.*?\'\'\'",'',s,flags=re.S)
s=re.sub(r'\"\"\".*?\"\"\"','',s,flags=re.S)
s=re.sub(r"\'(?:\\.|[^\\'])*\'",'',s)
s=re.sub(r'\"(?:\\.|[^\\"])*\"','',s)
lines=s.split('\n')
curly=0
for idx,l in enumerate(lines, start=1):
    opens=l.count('{')
    closes=l.count('}')
    if opens>0 or closes>0:
        curly += opens - closes
        print(f"{idx:5}: opens={opens} closes={closes} cumulative={curly} | {l.strip()}")
        if curly<0:
            break
print('done')
