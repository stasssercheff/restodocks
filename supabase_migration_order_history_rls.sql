-- Расширение RLS для order_history: сотрудники заведения могут просматривать,
-- создавать, редактировать и удалять заказы своего заведения.
-- Выполнить в SQL Editor Supabase после создания таблицы order_history.

-- Политика: сотрудники заведения видят заказы своего заведения
DROP POLICY IF EXISTS "Employees can view order history for their establishment" ON order_history;
CREATE POLICY "Employees can view order history for their establishment"
ON order_history FOR SELECT USING (
  establishment_id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
  )
  OR establishment_id IN (SELECT id FROM establishments WHERE owner_id = auth.uid())
);

-- Политика: сотрудники могут обновлять заказы своего заведения
DROP POLICY IF EXISTS "Employees can update orders for their establishment" ON order_history;
CREATE POLICY "Employees can update orders for their establishment"
ON order_history FOR UPDATE USING (
  establishment_id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
  )
  OR establishment_id IN (SELECT id FROM establishments WHERE owner_id = auth.uid())
);

-- Политика: сотрудники могут удалять заказы своего заведения
DROP POLICY IF EXISTS "Employees can delete orders for their establishment" ON order_history;
CREATE POLICY "Employees can delete orders for their establishment"
ON order_history FOR DELETE USING (
  establishment_id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
  )
  OR establishment_id IN (SELECT id FROM establishments WHERE owner_id = auth.uid())
);

-- Если политика INSERT была только для employees, оставляем как есть.
-- Иначе добавьте политику с WITH CHECK для сотрудников и владельца.
