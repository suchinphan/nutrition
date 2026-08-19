import sys
p='frontend/mobile/lib/page/Choose_food_type_page.dart'
s=open(p,encoding='utf-8').read()
# states
i=0
n=len(s)
par=0
curly=0
brack=0
in_s=None
in_comment=None
line=1
col=1
while i<n:
    ch=s[i]
    # track line/col
    if ch=='\n':
        line+=1; col=1
        if in_comment=='line': in_comment=None
        i+=1; continue
    if in_comment=='block':
        if ch=='*' and i+1<n and s[i+1]=='/': in_comment=None; i+=2; col+=2; continue
        i+=1; col+=1; continue
    if in_s:
        if ch=='\\':
            i+=2; col+=2; continue
        if ch==in_s:
            in_s=None
            i+=1; col+=1; continue
        i+=1; col+=1; continue
    # not in string or comment
    if ch=='/' and i+1<n and s[i+1]=='/': in_comment='line'; i+=2; col+=2; continue
    if ch=='/' and i+1<n and s[i+1]=='*': in_comment='block'; i+=2; col+=2; continue
    if ch=='"' or ch=="'":
        # detect triple
        if i+2<n and s[i+1]==ch and s[i+2]==ch:
            in_s=ch; i+=3; col+=3; continue
        in_s=ch; i+=1; col+=1; continue
    # count parens
    if ch=='(':
        par+=1
    elif ch==')':
        par-=1
        if par<0:
            print(f"Unmatched ')' at line {line} col {col}")
            sys.exit(0)
    elif ch=='{':
        curly+=1
    elif ch=='}':
        curly-=1
        if curly<0:
                print("Unmatched '}' at line", line, "col", col)
                # print context
                all_lines = s.split('\n')
                start = max(0, line-6)
                end = min(len(all_lines), line+3)
                print('\nContext:')
                for idx in range(start, end):
                    print(f"{idx+1}: {all_lines[idx]}")
                sys.exit(0)
    elif ch=='[':
        brack+=1
    elif ch==']':
        brack-=1
        if brack<0:
            print("Unmatched ']' at line", line, "col", col)
            sys.exit(0)
    i+=1; col+=1
# end loop
if par!=0 or curly!=0 or brack!=0:
    print('Final balances: ( ) ->',par,'{ } ->',curly,'[ ] ->',brack)
else:
    print('All balanced')
