-- Migration: add weight_goal to users — purely additive, no existing data touched.
-- Values: 'ลดน้ำหนัก' / 'รักษาน้ำหนัก' / 'เพิ่มน้ำหนัก' (NULL = not set yet, treated as maintain).
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS weight_goal VARCHAR(30) NULL;
