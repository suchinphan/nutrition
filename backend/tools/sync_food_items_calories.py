"""Audit + (optionally) fix food_items.calories against the Atwater
macro formula (health_calc.calc_calories_from_macros), per the single-
source-of-truth requirement for the calorie figure.

Default is report-only (dry run) — never writes to the DB unless --apply
is passed. Rows where protein_g == carbs_g == fat_g == 0 are reported
separately and never touched (no macros to derive a real value from —
guessing would be worse than leaving the stored value alone).

Usage:
    python tools/sync_food_items_calories.py            # report only
    python tools/sync_food_items_calories.py --apply     # write the fix
"""
import argparse
import sys
sys.path.insert(0, '.')

from api import app, db
from models import FoodItem
from health_calc import calc_calories_from_macros

MISMATCH_THRESHOLD_PCT = 10


def audit():
    rows = FoodItem.query.order_by(FoodItem.id).all()
    zero_macro, mismatches, ok = [], [], []
    for r in rows:
        p, cb, f = (r.protein_g or 0), (r.carbs_g or 0), (r.fat_g or 0)
        if p == 0 and cb == 0 and f == 0:
            zero_macro.append(r)
            continue
        expected = calc_calories_from_macros(cb, p, f)
        stored = r.calories or 0
        pct = (abs(expected - stored) / stored * 100) if stored else float('inf')
        (mismatches if pct > MISMATCH_THRESHOLD_PCT else ok).append((r, expected, pct))
    return rows, ok, mismatches, zero_macro


def report(rows, ok, mismatches, zero_macro):
    print(f'food_items total: {len(rows)}')
    print(f'  within {MISMATCH_THRESHOLD_PCT}% of macro-derived calories: {len(ok)}')
    print(f'  mismatch (> {MISMATCH_THRESHOLD_PCT}% diff): {len(mismatches)}')
    print(f'  zero-macro (protein=carbs=fat=0, skipped): {len(zero_macro)}')
    if mismatches:
        print('\n--- mismatches ---')
        for r, expected, pct in sorted(mismatches, key=lambda t: -t[2]):
            print(f'  id={r.id} name={r.name_th or r.name!r} stored={r.calories} '
                  f'expected={expected:.1f} diff={pct:.1f}%')
    if zero_macro:
        print('\n--- zero-macro rows (left untouched, needs manual data entry) ---')
        for r in zero_macro:
            print(f'  id={r.id} name={r.name_th or r.name!r} calories={r.calories}')


def apply_fix(rows_to_fix):
    for r, expected, _pct in rows_to_fix:
        r.calories = round(expected, 1)
    db.session.commit()
    print(f'\nApplied: updated calories on {len(rows_to_fix)} row(s).')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true', help='Write calories = macro-derived value (all non-zero-macro rows, not just mismatches)')
    args = parser.parse_args()

    with app.app_context():
        rows, ok, mismatches, zero_macro = audit()
        report(rows, ok, mismatches, zero_macro)
        if args.apply:
            apply_fix(ok + [(r, e, p) for r, e, p in mismatches])
        else:
            print('\nDry run only — no changes written. Re-run with --apply to write calories = macro-derived value.')
