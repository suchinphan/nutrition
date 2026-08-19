ALTER TABLE submissions
  ADD COLUMN reviewed_by INT DEFAULT NULL,
  ADD COLUMN review_note TEXT DEFAULT NULL,
  ADD COLUMN reviewed_at DATETIME DEFAULT NULL,
  ADD CONSTRAINT fk_submissions_reviewer FOREIGN KEY (reviewed_by)
    REFERENCES users(id);
