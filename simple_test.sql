-- ПРОСТОЙ ТЕСТ - ВЫПОЛНИ КАЖДЫЙ ЗАПРОС ОТДЕЛЬНО

-- 1. ПРОВЕРЬ ПОЛЬЗОВАТЕЛЯ
SELECT auth.uid();

-- 2. ПОДСЧИТАЙ ПРОДУКТЫ
SELECT COUNT(*) FROM products;

-- 3. ПОПРОБУЙ ЗАПРОС С ЛИМИТОМ
SELECT id, name FROM products LIMIT 1;

-- 4. ПРОВЕРЬ НОМЕНКЛАТУРУ
SELECT COUNT(*) FROM establishment_products WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';