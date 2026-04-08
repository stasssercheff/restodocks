-- Линтер Supabase 0013_rls_disabled_in_public: таблица в public без RLS.
-- Раньше стояло REVOKE ALL + RLS OFF; клиент ходит только в RPC (SECURITY DEFINER).
-- delete_owner_account_data — SECURITY INVOKER и делает DELETE по owner_id: нужна политика RLS.

ALTER TABLE public.establishment_data_clone_requests ENABLE ROW LEVEL SECURITY;

-- Удаление своих заявок при удалении аккаунта (invoker = authenticated).
CREATE POLICY establishment_data_clone_requests_owner_delete
  ON public.establishment_data_clone_requests
  FOR DELETE
  TO authenticated
  USING (owner_id = auth.uid());

COMMENT ON POLICY establishment_data_clone_requests_owner_delete
  ON public.establishment_data_clone_requests IS
  'Владелец удаляет заявки на клон при purge аккаунта (delete_owner_account_data).';

-- INSERT/SELECT/UPDATE по-прежнему только из SECURITY DEFINER RPC (владелец таблицы обходит RLS).
-- DELETE для invoker-функции: нужны право на таблицу и политика (только свои строки).
GRANT DELETE ON public.establishment_data_clone_requests TO authenticated;
