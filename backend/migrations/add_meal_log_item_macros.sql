ALTER TABLE meal_log_items
  ADD COLUMN protein_actual FLOAT DEFAULT NULL AFTER calories_actual,
  ADD COLUMN carbs_actual   FLOAT DEFAULT NULL AFTER protein_actual,
  ADD COLUMN fat_actual     FLOAT DEFAULT NULL AFTER carbs_actual;
