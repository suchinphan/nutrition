ALTER TABLE health_goal_cycles
  ADD COLUMN weight_start FLOAT NULL,
  ADD COLUMN weight_end FLOAT NULL,
  ADD COLUMN weight_delta FLOAT GENERATED ALWAYS AS (weight_end - weight_start) STORED;