-- Политики RLS для authenticated: график и списки заказов.
-- Без них при входе через Supabase Auth данные не читаются/не пишутся в Supabase,
-- остаётся только SharedPreferences — и при очистке кеша/новом устройстве всё слетает.

-- establishment_schedule_data (график смен)
DROP POLICY IF EXISTS "auth_schedule_select" ON establishment_schedule_data;
CREATE POLICY "auth_schedule_select" ON establishment_schedule_data
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_schedule_insert" ON establishment_schedule_data;
CREATE POLICY "auth_schedule_insert" ON establishment_schedule_data
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "auth_schedule_update" ON establishment_schedule_data;
CREATE POLICY "auth_schedule_update" ON establishment_schedule_data
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- establishment_order_list_data (списки заказов поставщикам)
DROP POLICY IF EXISTS "auth_order_list_select" ON establishment_order_list_data;
CREATE POLICY "auth_order_list_select" ON establishment_order_list_data
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_order_list_insert" ON establishment_order_list_data;
CREATE POLICY "auth_order_list_insert" ON establishment_order_list_data
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "auth_order_list_update" ON establishment_order_list_data;
CREATE POLICY "auth_order_list_update" ON establishment_order_list_data
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
