-- Закрываем полный anon-доступ к product_alias_rejections (чтение/запись чужих заведений).
-- Приложение работает с Supabase Auth: authenticated + привязка к заведению пользователя.

ALTER TABLE public.product_alias_rejections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "anon_insert_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_select_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_insert_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_update_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_delete_product_alias_rejections" ON public.product_alias_rejections;

-- Глобальные строки (establishment_id IS NULL) — видны всем залогиненным (общий словарь отказов).
-- Строки заведения — только своё заведение.
CREATE POLICY "auth_select_product_alias_rejections"
ON public.product_alias_rejections
FOR SELECT
TO authenticated
USING (
  establishment_id IS NULL
  OR establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "auth_insert_product_alias_rejections"
ON public.product_alias_rejections
FOR INSERT
TO authenticated
WITH CHECK (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "auth_update_product_alias_rejections"
ON public.product_alias_rejections
FOR UPDATE
TO authenticated
USING (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
)
WITH CHECK (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "auth_delete_product_alias_rejections"
ON public.product_alias_rejections
FOR DELETE
TO authenticated
USING (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
);
