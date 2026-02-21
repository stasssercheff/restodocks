-- СОЗДАТЬ ПРОСТУЮ ФУНКЦИЮ ДЛЯ ОТЛАДКИ ПРОДУКТОВ

CREATE OR REPLACE FUNCTION debug_products_access()
RETURNS TABLE (
    check_name text,
    result text,
    status text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_id uuid;
    products_count bigint;
    direct_query_count bigint;
BEGIN
    -- Получить текущего пользователя
    user_id := auth.uid();

    -- Посчитать продукты
    SELECT COUNT(*) INTO products_count FROM products;

    -- Попробовать прямой запрос
    SELECT COUNT(*) INTO direct_query_count FROM products;

    -- Вернуть результаты
    RETURN QUERY VALUES
        ('Current User', COALESCE(user_id::text, 'NULL'), CASE WHEN user_id IS NOT NULL THEN 'AUTHORIZED' ELSE 'NOT AUTHORIZED' END),
        ('Products in Table', products_count::text, CASE WHEN products_count > 0 THEN 'HAS PRODUCTS' ELSE 'NO PRODUCTS' END),
        ('Direct Query', direct_query_count::text, CASE WHEN direct_query_count > 0 THEN 'WORKS' ELSE 'FAILS' END),
        ('RLS Working', CASE WHEN direct_query_count = products_count THEN 'YES' ELSE 'NO' END, 'INFO');
END;
$$;

-- ВЫЗВАТЬ ФУНКЦИЮ
SELECT * FROM debug_products_access();