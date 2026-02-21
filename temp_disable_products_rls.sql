-- ВРЕМЕННО ОТКЛЮЧАЕМ RLS НА ПРОДУКТАХ ДЛЯ ДИАГНОСТИКИ
-- Выполнить в Supabase SQL Editor

-- Отключаем RLS на products
ALTER TABLE products DISABLE ROW LEVEL SECURITY;

-- Проверяем, что продукты есть в базе
SELECT COUNT(*) as total_products FROM products;

-- Показываем первые 10 продуктов
SELECT id, name, category, base_price, currency, created_at
FROM products
ORDER BY created_at DESC
LIMIT 10;

-- После проверки можно включить обратно:
-- ALTER TABLE products ENABLE ROW LEVEL SECURITY;
-- И вернуть политику:
-- CREATE POLICY "products_access" ON products FOR ALL USING (auth.uid() IS NOT NULL);