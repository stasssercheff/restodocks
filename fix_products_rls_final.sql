-- СРОЧНОЕ ИСПРАВЛЕНИЕ RLS ДЛЯ PRODUCTS
-- Выполнить в Supabase SQL Editor

-- 1. УДАЛИТЬ ВСЕ СТАРЫЕ ПОЛИТИКИ
DROP POLICY IF EXISTS "products_access" ON products;

-- 2. СОЗДАТЬ НОВУЮ ПОЛИТИКУ С WITH CHECK
CREATE POLICY "products_access" ON products
FOR ALL USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);

-- 3. ПРОВЕРИТЬ
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public'
    AND tablename = 'products';