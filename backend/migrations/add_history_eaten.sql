-- Migration: add is_eaten / eaten_at to histories — purely additive, no existing data touched.
-- Backs the "บันทึกเมนูไว้ (planned)" vs "ทานแล้ว (eaten)" distinction. Every history row
-- starts as planned (is_eaten=0) and is flipped to eaten via POST /history/<id>/mark-eaten.
-- The app dashboard (/api/dashboard) sums calories/sugar/sodium only for rows where is_eaten=1.
ALTER TABLE histories
  ADD COLUMN IF NOT EXISTS is_eaten TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS eaten_at DATETIME NULL;
