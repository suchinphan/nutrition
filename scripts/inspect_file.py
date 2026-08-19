from pathlib import Path
p=Path(r'c:/Users/USerZ/Downloads/NutritionalHealth/frontend/mobile/lib/page/personal_information_page.dart')
s=p.read_text()
for i,l in enumerate(s.splitlines(),1):
    if 'class _PersonalInformationPageState' in l or 'class PersonalInformationPage' in l or 'Widget build(' in l or 'void initState(' in l or 'void dispose(' in l:
        print(i, l)

print('\nTotal lines:', len(s.splitlines()))
print('Opens:', s.count('{'), 'Closes:', s.count('}'))
