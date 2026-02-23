-- ЧАСТЬ 2: Вставка базовых данных
-- Выполните после создания таблиц

-- Вставка базовых технологических процессов
INSERT INTO cooking_processes (name, localized_names, calorie_multiplier, protein_multiplier, fat_multiplier, carbs_multiplier, weight_loss_percentage, applicable_categories) VALUES
('Boiling', '{"ru": "Варка", "en": "Boiling"}', 0.95, 0.95, 0.90, 0.98, 25.0, ARRAY['vegetables', 'meat', 'fish', 'grains', 'pasta']),
('Frying', '{"ru": "Жарка", "en": "Frying"}', 1.10, 0.95, 1.20, 0.98, 15.0, ARRAY['meat', 'fish', 'vegetables']),
('Baking', '{"ru": "Запекание", "en": "Baking"}', 1.05, 0.98, 1.05, 0.97, 20.0, ARRAY['meat', 'fish', 'vegetables', 'dough']),
('Stewing', '{"ru": "Тушение", "en": "Stewing"}', 0.98, 0.97, 0.95, 0.99, 30.0, ARRAY['meat', 'vegetables']);