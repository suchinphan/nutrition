import csv
import io
from typing import List, Dict

def histories_to_csv_bytes(histories: List[Dict]) -> bytes:
    """
    histories: list of dicts with keys: id, user_id, data, created_at
    returns: CSV bytes (utf-8)
    """
    output = io.StringIO()
    writer = csv.writer(output)
    # header
    writer.writerow(['id', 'user_id', 'created_at', 'data'])
    for h in histories:
        writer.writerow([h.get('id'), h.get('user_id'), h.get('created_at'), h.get('data')])
    return output.getvalue().encode('utf-8')

def csv_bytes_to_users_list(csv_bytes: bytes) -> List[Dict]:
    """
    Parse uploaded CSV bytes into list of user dicts.
    Expected CSV columns: username,email,password (password optional)
    """
    text = csv_bytes.decode('utf-8-sig')
    reader = csv.DictReader(io.StringIO(text))
    users = []
    for row in reader:
        # normalize keys
        username = row.get('username') or row.get('user') or row.get('ชื่อ') or row.get('name')
        email = row.get('email') or row.get('อีเมล')
        password = row.get('password') or row.get('pass') or row.get('รหัสผ่าน')
        if username:
            users.append({'username': username.strip(), 'email': (email or '').strip(), 'password': (password or '').strip()})
    return users

def histories_to_excel_bytes(histories: List[Dict]) -> bytes:
    """
    Export histories to Excel bytes using pandas if available.
    Falls back to CSV bytes with .csv extension if pandas not installed.
    """
    try:
        import pandas as pd
    except Exception as e:
        raise RuntimeError('pandas required for Excel export') from e

    df = pd.DataFrame(histories)
    output = io.BytesIO()
    with pd.ExcelWriter(output, engine='openpyxl') as writer:
        df.to_excel(writer, index=False, sheet_name='histories')
    return output.getvalue()
