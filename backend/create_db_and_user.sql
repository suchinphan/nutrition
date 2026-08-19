-- Edit the placeholders below before running, or run as-is and replace names afterwards.
-- Run with: mysql -u root -p < create_db_and_user.sql

CREATE DATABASE IF NOT EXISTS nutrition_app CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create an app user bound to 127.0.0.1 (use a strong password)
CREATE USER IF NOT EXISTS 'appuser'@'127.0.0.1' IDENTIFIED BY 'StrongP@ssw0rd!';
GRANT ALL PRIVILEGES ON nutrition_app.* TO 'appuser'@'127.0.0.1';
FLUSH PRIVILEGES;

ALTER USER 'appuser'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY 'StrongP@ssw0rd!';
FLUSH PRIVILEGES;

-- Optional: show databases and grants
SHOW DATABASES;
SHOW GRANTS FOR 'appuser'@'127.0.0.1';
