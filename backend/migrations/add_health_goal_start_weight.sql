ALTER TABLE users ADD COLUMN health_goal_start_weight FLOAT NULL;
-- Snapshot the profile weight when a health-goal cycle starts so progress
-- can be evaluated independently from the target weight and later weigh-ins.
