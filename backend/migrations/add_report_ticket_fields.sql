-- Migration: add subject + status to reports — reframes chat-thread rows as tickets.
-- Purely additive, no existing data touched. One reports row = one issue a user raised.
-- status values: 'pending' (รอตรวจ) / 'answered' (ตอบแล้ว) / 'closed' (ปิดเรื่อง).
ALTER TABLE reports
  ADD COLUMN IF NOT EXISTS subject VARCHAR(200) NULL,
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'pending';
