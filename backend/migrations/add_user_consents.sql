CREATE TABLE user_consents (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  consent_type VARCHAR(50) NOT NULL DEFAULT 'health_data_pdpa',
  policy_version VARCHAR(20) NOT NULL,
  consented_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_consent_user FOREIGN KEY (user_id)
    REFERENCES users(id) ON DELETE CASCADE
);
