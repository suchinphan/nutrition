-- Migration: remove the badges/streak (gamification) feature — cut per
-- instructor's direction. Confirmed no important/production data in these
-- tables before writing this migration.
-- Drop order matters: user_badges/user_streaks both FK to users, no other
-- table references them, so a plain DROP is safe.

DROP TABLE IF EXISTS user_badges;
DROP TABLE IF EXISTS user_streaks;
