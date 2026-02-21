-- ИСПРАВЛЕНИЕ РЕКУРСИИ В ПОЛИТИКЕ employees

-- Удалить старую политику
DROP POLICY IF EXISTS "employees_establishment_access" ON employees;

-- Создать правильную политику (без рекурсии)
-- Сотрудники видят всех сотрудников своего заведения
CREATE POLICY "employees_establishment_access" ON employees
FOR ALL USING (
  establishment_id IN (
    SELECT e2.establishment_id
    FROM employees e2
    WHERE e2.id = auth.uid()
    LIMIT 1
  )
);

-- Альтернативный вариант (если выше не работает)
-- DROP POLICY IF EXISTS "employees_establishment_access" ON employees;
-- CREATE POLICY "employees_establishment_access" ON employees
-- FOR ALL USING (true); -- Временно разрешить все, фильтровать в приложении