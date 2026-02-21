-- ПОЛНАЯ ДИАГНОСТИКА ПРОБЛЕМЫ С ПРОДУКТАМИ

-- 1. ТЕКУЩИЙ ПОЛЬЗОВАТЕЛЬ
SELECT
    'Current User ID' as check_type,
    auth.uid() as result,
    CASE WHEN auth.uid() IS NOT NULL THEN 'AUTHORIZED' ELSE 'NOT AUTHORIZED' END as status;

-- 2. КОЛИЧЕСТВО ПРОДУКТОВ
SELECT
    'Products Count' as check_type,
    COUNT(*) as result,
    CASE WHEN COUNT(*) > 0 THEN 'HAS PRODUCTS' ELSE 'NO PRODUCTS' END as status
FROM products;

-- 3. RLS ПОЛИТИКА
SELECT
    'RLS Policy' as check_type,
    STRING_AGG(policyname, ', ') as result,
    CASE WHEN COUNT(*) > 0 THEN 'HAS POLICY' ELSE 'NO POLICY' END as status
FROM pg_policies
WHERE tablename = 'products';

-- 4. ПРЯМОЙ ЗАПРОС (ТОТ ЖЕ ЧТО ДЕЛАЕТ loadProducts)
SELECT
    'Direct Query' as check_type,
    COUNT(*) as result,
    CASE WHEN COUNT(*) > 0 THEN 'WORKS' ELSE 'FAILS' END as status
FROM products;

-- 5. НОМЕНКЛАТУРА
SELECT
    'Nomenclature' as check_type,
    COUNT(*) as result,
    CASE WHEN COUNT(*) > 0 THEN 'HAS NOMENCLATURE' ELSE 'NO NOMENCLATURE' END as status
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- 6. СООТВЕТСТВИЕ ПРОДУКТОВ
SELECT
    'Product Match' as check_type,
    CONCAT(
        COUNT(CASE WHEN p.id IS NOT NULL THEN 1 END)::text,
        '/',
        COUNT(*)::text
    ) as result,
    CASE
        WHEN COUNT(CASE WHEN p.id IS NOT NULL THEN 1 END) = COUNT(*) THEN 'ALL MATCH'
        ELSE 'SOME MISSING'
    END as status
FROM establishment_products ep
LEFT JOIN products p ON ep.product_id = p.id
WHERE ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';