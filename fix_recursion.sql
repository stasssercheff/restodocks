-- ИСПРАВЛЕНИЕ БЕСКОНЕЧНОЙ РЕКУРСИИ В RLS ПОЛИТИКАХ

-- Удаляем проблемную политику
DROP POLICY IF EXISTS "employees_access" ON employees;

-- Создаем правильную политику без рекурсии
-- Пользователь может читать/писать:
-- 1. Свои собственные данные (id = auth.uid())
-- 2. Другие сотрудники из того же заведения (через establishments)
CREATE POLICY "employees_access_fixed" ON employees
FOR ALL USING (
    id = auth.uid()
    OR establishment_id IN (
        SELECT e2.establishment_id
        FROM employees e2
        WHERE e2.id = auth.uid()
    )
);

-- Проверяем политику
SELECT
    schemaname,
    tablename,
    policyname,
    qual
FROM pg_policies
WHERE tablename = 'employees';