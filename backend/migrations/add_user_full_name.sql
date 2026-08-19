-- Migration: add full_name to users — purely additive, no existing data touched.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS full_name VARCHAR(150) NULL;
