CREATE TABLE user_favorite_foods (
  user_id INT NOT NULL,
  food_item_id INT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, food_item_id),
  CONSTRAINT fk_fav_user FOREIGN KEY (user_id)
    REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_fav_food FOREIGN KEY (food_item_id)
    REFERENCES food_items(id) ON DELETE CASCADE
);
