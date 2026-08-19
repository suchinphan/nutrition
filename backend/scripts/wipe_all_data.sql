-- Deletes every row from every table in nutrition_app — tables/schema are
-- kept intact, only data is removed. TRUNCATE also resets AUTO_INCREMENT
-- counters so new data starts from id=1 again.
-- Run against the database configured in backend/mysql_config.json.
-- IRREVERSIBLE — take a backup first if any of this data matters.

SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE TABLE profile_audit_log;
TRUNCATE TABLE user_selections;
TRUNCATE TABLE submissions;
TRUNCATE TABLE histories;
TRUNCATE TABLE reports;
TRUNCATE TABLE food_menus;
TRUNCATE TABLE dessert_menus;
TRUNCATE TABLE drink_menus;
TRUNCATE TABLE food_categories;
TRUNCATE TABLE food_types;
TRUNCATE TABLE drink_types;
TRUNCATE TABLE users;

SET FOREIGN_KEY_CHECKS = 1;
