-- auth_update_employees (20260430210000) разрешает UPDATE, если id = auth.uid()
-- ИЛИ (auth_user_id IS NOT NULL AND auth_user_id = auth.uid()).
-- auth_select_employees (старый) разрешал SELECT только по id = auth.uid()
-- ИЛИ establishment_id IN (current_user_establishment_ids()).
-- Если у строки establishment_id NULL (или иной крайний legacy), а связь только по auth_user_id,
-- UPDATE проходит, а PostgREST SELECT после PATCH возвращает 0 строк — клиент видит «не сохранилось».

DROP POLICY IF EXISTS "auth_select_employees" ON public.employees;
CREATE POLICY "auth_select_employees" ON public.employees
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR (
      auth_user_id IS NOT NULL
      AND auth_user_id = auth.uid()
    )
    OR establishment_id IN (SELECT public.current_user_establishment_ids())
  );
