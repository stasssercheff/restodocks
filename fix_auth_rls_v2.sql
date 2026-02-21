-- ИСПРАВЛЕНИЕ RLS ПОЛИТИК ДЛЯ АВТОРИЗАЦИИ V2

-- Сначала проверить существующие политики
SELECT tablename, policyname FROM pg_policies WHERE tablename IN ('employees', 'establishments');

-- Удалить ВСЕ политики для этих таблиц
DROP POLICY IF EXISTS "employees_establishment_access" ON employees;
DROP POLICY IF EXISTS "employees_access" ON employees;
DROP POLICY IF EXISTS "establishments_owner_access" ON establishments;
DROP POLICY IF EXISTS "establishments_access" ON establishments;

-- Создать правильные политики
-- Employees: пользователь может читать/писать всех сотрудников своего заведения И СЕБЯ
CREATE POLICY "employees_access_policy" ON employees
FOR ALL USING (
    establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
    OR id = auth.uid()  -- Пользователь может читать/писать себя
);

-- Establishments: владелец может читать/писать свое заведение
CREATE POLICY "establishments_access_policy" ON establishments
FOR ALL USING (
    id IN (
        SELECT establishment_id FROM employees
        WHERE id = auth.uid() AND 'owner' = ANY(roles)
    )
);

-- Проверить финальные политики
SELECT
    tablename,
    policyname,
    qual
FROM pg_policies
WHERE tablename IN ('employees', 'establishments')
ORDER BY tablename;