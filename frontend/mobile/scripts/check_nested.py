path = r"c:\Users\USerZ\Downloads\NutritionalHealth\NutritionalHealth\frontend\mobile\lib\page\Choose_food_type_page.dart"
s = open(path, 'r', encoding='utf-8').read()
start_an = s.find('Future<void> _analyzeMenu(')
open_an = s.find('{', start_an)
stack=0
end_an=None
for i in range(open_an, len(s)):
    if s[i]=='{': stack+=1
    elif s[i]=='}': stack-=1
    if stack==0:
        end_an=i
        break
start_auth = s.find('void _authListener()')
print('analyze start line', s[:start_an].count('\n')+1)
print('analyze end line', s[:end_an].count('\n')+1)
print('authListener line', s[:start_auth].count('\n')+1)
print('authListener inside analyze?', start_auth>start_an and start_auth<end_an)
PY