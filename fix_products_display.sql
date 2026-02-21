-- ИСПРАВЛЕНИЕ ОТОБРАЖЕНИЯ ПРОДУКТОВ

-- Временно отключить RLS на products для тестирования
ALTER TABLE products DISABLE ROW LEVEL SECURITY;

-- Проверить что продукты появились
SELECT COUNT(*) as products_count FROM products;