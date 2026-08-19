import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
api_path = str(ROOT / 'backend' / 'api.py')
models_path = str(ROOT / 'backend' / 'models.py')

spec = importlib.util.spec_from_file_location('backend_models', models_path)
models = importlib.util.module_from_spec(spec)
spec.loader.exec_module(models)
import sys
# Make models importable as top-level 'models' for backend/api.py
sys.modules['models'] = models

spec2 = importlib.util.spec_from_file_location('backend_api', api_path)
api = importlib.util.module_from_spec(spec2)
# Ensure backend directory is on sys.path so relative imports inside api.py work
backend_dir = str(ROOT / 'backend')
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)
spec2.loader.exec_module(api)

app = getattr(api, 'app', None)
if app is None:
    print('Could not find app in backend/api.py')
    sys.exit(1)

with app.app_context():
    History = models.History
    User = models.User
    h = History.query.get(92)
    print('History exists:', bool(h))
    if not h:
        print('No history id=92')
    else:
        print('history.id=', h.id)
        print('history.user_id=', h.user_id)
        data = h.data
        try:
            import json
            parsed = json.loads(data) if isinstance(data, str) else data
            if isinstance(parsed, dict):
                print('history.data keys:', list(parsed.keys()))
            else:
                print('history.data (str):', str(parsed)[:500])
        except Exception:
            print('history.data (raw):', str(data)[:500])
        u = User.query.get(h.user_id)
        print('User found:', bool(u))
        if u:
            print('user.id=', u.id)
            print('username=', u.username)
            print('height=', u.height)
            print('weight=', u.weight)
            print('bmi=', u.bmi)
            print('bmi_status=', u.bmi_status)
