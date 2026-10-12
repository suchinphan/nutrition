"""Trained menu recommender used by the existing recommendation endpoint."""

from sklearn.ensemble import RandomForestClassifier


def _features(item, target_calories):
    calories = float(item.calories or 0)
    return [
        calories,
        float(item.protein_g or 0),
        float(item.fat_g or 0),
        float(item.carbs_g or 0),
        float(item.fiber_g or 0),
        float(item.sugar_g or 0),
        calories - float(target_calories or 0),
    ]


def trained_scores(candidates, positive_food_ids, negative_food_ids, target_calories):
    """Return learned probabilities using only explicit positive/negative signals."""
    positive_ids = {int(food_id) for food_id in positive_food_ids}
    negative_ids = {int(food_id) for food_id in negative_food_ids} - positive_ids
    labeled_candidates = [
        item for item in candidates
        if item.id in positive_ids or item.id in negative_ids
    ]
    labels = [1 if item.id in positive_ids else 0 for item in labeled_candidates]
    if len(set(labels)) < 2:
        return None

    model = RandomForestClassifier(
        n_estimators=100,
        random_state=42,
        class_weight='balanced',
    )
    model.fit(
        [_features(item, target_calories) for item in labeled_candidates],
        labels,
    )
    positive_column = list(model.classes_).index(1)
    learned = {
        item.id: round(float(probabilities[positive_column]), 6)
        for item, probabilities in zip(candidates, model.predict_proba(
            [_features(item, target_calories) for item in candidates]
        ))
    }
    return learned
