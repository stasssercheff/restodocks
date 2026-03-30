-- Самообновление профиля (должность, first_session_at): JWT совпадает с employees.auth_user_id,
-- при этом в редких схемах id строки мог расходиться с auth.uid() → 0 rows updated.
-- Разрешаем UPDATE, если строка принадлежит текущему пользователю по id или auth_user_id.

DROP POLICY IF EXISTS "auth_update_employees" ON public.employees;
CREATE POLICY "auth_update_employees" ON public.employees
  FOR UPDATE TO authenticated
  USING (
    id = auth.uid()
    OR (
      auth_user_id IS NOT NULL
      AND auth_user_id = auth.uid()
    )
  )
  WITH CHECK (
    id = auth.uid()
    OR (
      auth_user_id IS NOT NULL
      AND auth_user_id = auth.uid()
    )
  );
