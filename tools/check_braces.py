import sys
p = r'c:\Users\USerZ\Downloads\NutritionalHealth\frontend\mobile\lib\page\personal_information_page.dart'
try:
    s = open(p, encoding='utf-8').read()
except Exception as e:
    print('ERROR opening file:', e)
    sys.exit(2)
stack = []
issues = []
for i, ch in enumerate(s, 1):
    if ch == '{':
        stack.append(i)
    elif ch == '}':
        if stack:
            stack.pop()
        else:
            issues.append(('unmatched_closing', i))
if stack:
    issues.append(('unmatched_opening', stack))
print('issues:', issues)
if issues:
    for t, v in issues:
        if t == 'unmatched_opening':
            print('Unmatched opening positions sample (first 10):', v[:10])
            for pos in v[:10]:
                line = s.count('\n', 0, pos) + 1
                col = pos - (s.rfind('\n', 0, pos))
                snippet = s[max(0, pos-60):pos+60]
                print(f' at char {pos} -> line {line}, col {col}\n  snippet: {repr(snippet)}')
        else:
            line = s.count('\n', 0, v) + 1
            col = v - (s.rfind('\n', 0, v))
            snippet = s[max(0, v-60):v+60]
            print(f'Unmatched closing at char {v} -> line {line}, col {col}\n  snippet: {repr(snippet)}')
else:
    print('No brace issues found')
# also check parentheses and brackets counts
print('\nParentheses and brackets counts:')
print('(', s.count('('), ')', s.count(')'))
print('[', s.count('['), ']', s.count(']'))
print('{', s.count('{'), '}', s.count('}'))
