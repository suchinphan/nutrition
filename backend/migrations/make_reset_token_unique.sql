-- Migration: ensure reset_token and password_token uniqueness and add reset_token_expires_at if missing
-- Run on a safe maintenance window. Review results before applying unique constraints.

-- 1) Find duplicate reset_token_hash values
SELECT reset_token_hash, COUNT(*) AS c
FROM users
WHERE reset_token_hash IS NOT NULL
GROUP BY reset_token_hash
HAVING c > 1;

-- If duplicates exist, inspect them and decide which to keep. The example below keeps the latest id and nulls others.
-- WARNING: Adjust logic based on your data retention rules.

-- Example: keep the highest id for each reset_token_hash and null others
UPDATE users u
JOIN (
  SELECT reset_token_hash, MAX(id) AS keep_id
  FROM users
  WHERE reset_token_hash IS NOT NULL
  GROUP BY reset_token_hash
) t ON u.reset_token_hash = t.reset_token_hash
SET u.reset_token_hash = NULL
WHERE u.id <> t.keep_id;

-- 2) Add unique indexes (will fail if duplicates remain)
ALTER TABLE users
  ADD UNIQUE INDEX ux_users_reset_token_hash (reset_token_hash);

ALTER TABLE users
  ADD UNIQUE INDEX ux_users_password_token (password_token);

-- 3) Ensure reset_token_expires_at exists
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS reset_token_expires_at DATETIME NULL;

-- After running, verify:
-- SELECT reset_token, COUNT(*) FROM users WHERE reset_token IS NOT NULL GROUP BY reset_token HAVING COUNT(*)>1;
-- SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name='users' AND index_name='ux_users_reset_token';
