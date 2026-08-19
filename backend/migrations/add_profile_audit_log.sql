-- Migration: add profile_audit_log table (read-only admin history feature)
-- Purely additive — no existing data touched. Safe to run anytime.
-- Backing table for models.ProfileAuditLog: one row per personal-info field
-- a user changes via POST /user/<id>. Nothing in the app ever UPDATEs or
-- DELETEs rows here — it's append-only, written once at insert time.

CREATE TABLE IF NOT EXISTS profile_audit_log (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  field_name VARCHAR(50) NOT NULL,
  old_value TEXT NULL,
  new_value TEXT NULL,
  changed_at DATETIME NULL,
  INDEX ix_profile_audit_log_user_id (user_id),
  INDEX ix_profile_audit_log_changed_at (changed_at),
  CONSTRAINT fk_profile_audit_log_user
    FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
