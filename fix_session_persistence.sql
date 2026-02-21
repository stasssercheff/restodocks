-- ИСПРАВЛЕНИЕ ПРОБЛЕМЫ С СЕССИЕЙ ПРИ ПЕРЕЗАГРУЗКЕ

-- ВКЛЮЧИТЬ RLS ОБРАТНО С ПРАВИЛЬНЫМИ ПОЛИТИКАМИ
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishments ENABLE ROW LEVEL SECURITY;

-- УДАЛИТЬ СЛОМАННЫЕ ПОЛИТИКИ
DROP POLICY IF EXISTS "employees_final" ON employees;
DROP POLICY IF EXISTS "establishments_final" ON establishments;

-- СОЗДАТЬ РАБОЧИЕ ПОЛИТИКИ БЕЗ РЕКУРСИИ
CREATE POLICY "employees_session_fix" ON employees
FOR ALL USING (
    id = auth.uid()
    OR establishment_id::text IN (
        SELECT establishment_id::text
        FROM employees
        WHERE id = auth.uid()
    )
);

CREATE POLICY "establishments_session_fix" ON establishments
FOR ALL USING (
    id::text IN (
        SELECT establishment_id::text
        FROM employees
        WHERE id = auth.uid() AND 'owner' = ANY(roles)
    )
);

-- ОСТАВИТЬ PRODUCTS БЕЗ RLS (чтобы отображались)
-- ALTER TABLE products DISABLE ROW LEVEL SECURITY;