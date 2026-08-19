import urllib.request, urllib.parse

def get(url):
    with urllib.request.urlopen(url) as r:
        print('STATUS', r.status)
        data = r.read().decode('utf-8')
        print(data[:10000])

if __name__ == '__main__':
    base = 'http://127.0.0.1:5000'
    for cat in ['อาหารลดน้ำหนัก', 'อาหารครบ 5 หมู่', 'อาหารสร้างกล้ามเนื้อ']:
        url = base + '/menus?category=' + urllib.parse.quote(cat)
        print('\nQUERY:', cat)
        try:
            get(url)
        except Exception as e:
            print('ERROR', e)
    print('\nDRINKS')
    try:
        get(base + '/drink-menus?type=' + urllib.parse.quote('เครื่องดื่มลดน้ำหนัก'))
    except Exception as e:
        print('ERROR', e)
    print('\nDESSERTS')
    try:
        get(base + '/desserts')
    except Exception as e:
        print('ERROR', e)
