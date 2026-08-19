import json
import os
import sys

try:
    import pymysql
except Exception:
    print('MISSING_PYMYSQL')
    sys.exit(2)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
cfg_path = os.path.join(BASE_DIR, 'mysql_config.json')
if not os.path.exists(cfg_path):
    print('NO_CONFIG')
    sys.exit(1)

with open(cfg_path, 'r', encoding='utf-8') as f:
    cfg = json.load(f)

host = cfg.get('host', '127.0.0.1')
port = int(cfg.get('port', 3306))
user = cfg.get('user')
passwd = cfg.get('password')
dbname = cfg.get('database')

print('CONNECT', host, port, user, dbname)

conn = pymysql.connect(host=host, port=port, user=user, password=passwd, database=dbname, charset='utf8mb4')
cur = conn.cursor()

def q(sql, params=None):
    cur.execute(sql, params or ())
    return cur

# 1) Check for existing food_menus with name or search_name like '%ข้าว%'
q("SELECT id, name, search_name, is_dessert, food_type_id, category_id FROM food_menus WHERE name LIKE %s OR (search_name IS NOT NULL AND search_name LIKE %s) LIMIT 100", ("%ข้าว%","%ข้าว%"))
rows = cur.fetchall()
print('FOUND_ROWS', len(rows))
for r in rows:
    print(r)

# 2) Check specific exact matches for 'ข้าว' and 'ข้าวไข่เจียว'
q("SELECT id, name, search_name, is_dessert FROM food_menus WHERE name = %s OR name = %s OR (search_name = %s) OR (search_name = %s)", ('ข้าว','ข้าวไข่เจียว','ข้าว','ข้าวไข่เจียว'))
exacts = cur.fetchall()
print('EXACT_MATCHES', len(exacts))
for r in exacts:
    print(r)

if exacts:
    print('Already have exact matches; exiting')
    conn.close()
    sys.exit(0)

# 3) Find or create a food_type and category to use
q('SELECT id, name FROM food_types LIMIT 10')
ft = cur.fetchall()
if ft:
    ft_id = ft[0][0]
    print('USE_EXISTING_FOOD_TYPE', ft[0])
else:
    print('No food_type present, creating test type')
    q('INSERT INTO food_types (name) VALUES (%s)', ('ทดสอบ',))
    conn.commit()
    ft_id = cur.lastrowid

# Find or create a category
q('SELECT id, name FROM food_categories WHERE food_type_id = %s LIMIT 10', (ft_id,))
cats = cur.fetchall()
if cats:
    cat_id = cats[0][0]
    print('USE_EXISTING_CATEGORY', cats[0])
else:
    print('No category for food_type, creating test category')
    q('INSERT INTO food_categories (food_type_id, name) VALUES (%s, %s)', (ft_id, 'ทดสอบคาว'))
    conn.commit()
    cat_id = cur.lastrowid

# 4) Insert test menu(s)
try:
    print('Inserting test menus')
    q('INSERT INTO food_menus (food_type_id, category_id, name, search_name, image_url, calories, protein, carbs, fat, is_dessert) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)',
      (ft_id, cat_id, 'ข้าวไข่เจียว', 'ข้าวไข่เจียว', '', 350.0, 12.0, 40.0, 15.0, 0))
    q('INSERT INTO food_menus (food_type_id, category_id, name, search_name, image_url, calories, protein, carbs, fat, is_dessert) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)',
      (ft_id, cat_id, 'ข้าวผัด', 'ข้าวผัด', '', 420.0, 10.0, 50.0, 18.0, 0))
    conn.commit()
    print('Inserted test menus')
except Exception as e:
    print('INSERT_ERROR', e)
    conn.rollback()

# 5) Re-query to confirm
q("SELECT id, name, search_name, is_dessert FROM food_menus WHERE name LIKE %s OR (search_name IS NOT NULL AND search_name LIKE %s) LIMIT 100", ("%ข้าว%","%ข้าว%"))
rows2 = cur.fetchall()
print('FOUND_AFTER_INSERT', len(rows2))
for r in rows2:
    print(r)

conn.close()
print('DONE')
