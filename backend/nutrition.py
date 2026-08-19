"""Nutrition classification helpers.

Provide `classify_nutrition(item)` which returns a dict with keys:
 - `tags`: list of Thai tags like "โปรตีน", "คาร์โบไฮเดรต", "พลังงานสูง", source tags like "โปรตีนจากไข่"
 - `summary`: short Thai summary string describing main macros and kcal

Designed to be defensive about missing fields and compatible with FoodMenu, DessertMenu, DrinkMenu.
"""
from typing import List, Dict

def _get_numeric(item, names, default=None):
    for n in names:
        if hasattr(item, n):
            try:
                v = getattr(item, n)
                if v is None:
                    continue
                return float(v)
            except Exception:
                continue
    return default

def classify_nutrition(item) -> Dict[str, object]:
    tags: List[str] = []
    # read common numeric fields with fallbacks
    protein = _get_numeric(item, ['protein', 'protein_g', 'proteinG'], default=None)
    carbs = _get_numeric(item, ['carbs', 'carbs_g', 'carb', 'carb_g'], default=None)
    fat = _get_numeric(item, ['fat', 'fat_g'], default=None)
    calories = _get_numeric(item, ['calories', 'kcal'], default=None)
    fiber = _get_numeric(item, ['fiber', 'fiber_g', 'fiber_g'], default=None)

    name = (getattr(item, 'search_name', None) or getattr(item, 'name', '') or '').lower()

    # Macronutrient tags (thresholds are intentionally simple)
    if protein is not None and protein >= 8:
        tags.append('โปรตีน')
    elif protein is not None and protein > 0:
        tags.append('มีโปรตีน')

    if carbs is not None and carbs >= 15:
        tags.append('คาร์โบไฮเดรต')
    elif carbs is not None and carbs > 0:
        tags.append('มีคาร์โบไฮเดรต')

    if fat is not None and fat >= 10:
        tags.append('ไขมัน')
    elif fat is not None and fat > 0:
        tags.append('มีไขมัน')

    # Energy density
    if calories is not None:
        if calories >= 400:
            tags.append('พลังงานสูง')
        elif calories >= 250:
            tags.append('พลังงานปานกลาง')
        else:
            tags.append('พลังงานต่ำ')

    # Vegetables / fruits cues
    veg_keys = ['ผัก', 'ผลไม้', 'salad', 'vegetable', 'fruit']
    if any(k in name for k in veg_keys):
        tags.append('ผัก/ผลไม้')
        if fiber is not None and fiber >= 3:
            tags.append('ไฟเบอร์สูง')

    # Source-based tags from name heuristics
    if 'ไข่' in name or 'egg' in name:
        tags.append('โปรตีนจากไข่')
    if 'ข้าว' in name or 'rice' in name:
        tags.append('คาร์บจากข้าว')
    if 'ปลา' in name or 'fish' in name:
        tags.append('โปรตีนจากปลา')
    if 'ไก่' in name or 'chicken' in name:
        tags.append('โปรตีนจากไก่')
    if 'tofu' in name or 'เต้าหู้' in name:
        tags.append('โปรตีนจากเต้าหู้')

    # Deduplicate while preserving order
    seen = set()
    tags_clean: List[str] = []
    for t in tags:
        if t not in seen:
            tags_clean.append(t)
            seen.add(t)

    # Build a concise summary in Thai
    parts = []
    if 'โปรตีน' in tags_clean or 'มีโปรตีน' in tags_clean:
        parts.append('ให้โปรตีน')
    if 'คาร์โบไฮเดรต' in tags_clean or 'มีคาร์โบไฮเดรต' in tags_clean:
        parts.append('คาร์โบไฮเดรต')
    if 'ไขมัน' in tags_clean or 'มีไขมัน' in tags_clean:
        parts.append('ไขมัน')

    kcal_part = ''
    if calories is not None:
        try:
            kcal_part = f' ~{int(round(calories))} kcal'
        except Exception:
            kcal_part = ''

    if parts:
        summary = 'เมนูนี้ให้' + ' และ '.join(parts) + ' เป็นแหล่งพลังงานหลัก' + (kcal_part or '')
    elif kcal_part:
        summary = 'เมนูนี้มีพลังงาน' + kcal_part
    else:
        summary = 'ไม่มีข้อมูลโภชนาการเพียงพอ'

    return {'tags': tags_clean, 'summary': summary}
