import os
import json
from sqlalchemy import create_engine, MetaData, Table, select, text
from urllib.parse import quote_plus

BASE_DIR = os.path.dirname(__file__)
DB_PATH = os.path.join(BASE_DIR, 'data.db')
CFG_PATH = os.path.join(BASE_DIR, 'mysql_config.json')


def get_mysql_uri_from_config():
    if not os.path.exists(CFG_PATH):
        raise RuntimeError(f'mysql_config.json not found at {CFG_PATH}')
    with open(CFG_PATH, 'r', encoding='utf-8') as f:
        cfg = json.load(f)
    user = cfg.get('user') or cfg.get('username')
    pw = cfg.get('password') or cfg.get('pass')
    host = cfg.get('host', '127.0.0.1')
    port = str(cfg.get('port', 3306))
    db = cfg.get('database') or cfg.get('db')
    if not all([user, pw, db]):
        raise RuntimeError('mysql_config.json must include user, password and database')
    pw_quoted = quote_plus(pw)
    return f'mysql+pymysql://{user}:{pw_quoted}@{host}:{port}/{db}?charset=utf8mb4'


def main():
    import argparse
    parser = argparse.ArgumentParser(description='Migrate users from local SQLite to MySQL using mysql_config.json')
    parser.add_argument('--preview', action='store_true', help='Show users that would be migrated and exit')
    parser.add_argument('--preserve-ids', action='store_true', help='Preserve original SQLite ids when inserting into MySQL')
    parser.add_argument('--migrate', action='store_true', help='Perform the migration (omit to only preview)')
    args = parser.parse_args()

    sqlite_uri = f'sqlite:///{DB_PATH}'
    print('Connecting to SQLite:', sqlite_uri)
    sqlite_engine = create_engine(sqlite_uri)

    mysql_uri = get_mysql_uri_from_config()
    print('Connecting to MySQL:', mysql_uri)
    mysql_engine = create_engine(mysql_uri)

    meta_sqlite = MetaData()
    meta_mysql = MetaData()

    users_sqlite = Table('users', meta_sqlite, autoload_with=sqlite_engine)
    users_mysql = Table('users', meta_mysql, autoload_with=mysql_engine)

    with sqlite_engine.connect() as sconn, mysql_engine.connect() as mconn:
        rows = sconn.execute(select(users_sqlite)).fetchall()
        print(f'Found {len(rows)} users in SQLite')
        if not rows:
            return
        preview_list = []
        for r in rows:
            try:
                d = dict(r._mapping)
            except Exception:
                d = dict(r)
            preview_list.append({'username': d.get('username'), 'email': d.get('email'), 'id': d.get('id')})

        print('Previewing up to first 50 users:')
        for p in preview_list[:50]:
            print(p)
        print(f'Total: {len(preview_list)}')

        if args.preview and not args.migrate:
            print('\nRun with --migrate to perform migration')
            return

        # Perform migration
        inserted = 0
        for r in rows:
            try:
                data = dict(r._mapping)
            except Exception:
                data = dict(r)
            username = data.get('username')
            if not username:
                continue
            exists = mconn.execute(select(users_mysql.c.username).where(users_mysql.c.username == username)).fetchone()
            if exists:
                continue
            if args.preserve_ids:
                mconn.execute(users_mysql.insert().values(**data))
            else:
                data.pop('id', None)
                mconn.execute(users_mysql.insert().values(**data))
            inserted += 1
        print(f'Inserted {inserted} new users into MySQL')

    print('Migration completed (preview/migrate finished).')


if __name__ == '__main__':
    main()
