-- ФИНАЛЬНОЕ ИСПРАВЛЕНИЕ - ОТКЛЮЧИТЬ RLS НА PRODUCTS

ALTER TABLE products DISABLE ROW LEVEL SECURITY;

-- Проверить что продукты появились
SELECT COUNT(*) as products_count FROM products;