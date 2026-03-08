-- Legacy-логин (authenticate-employee) не даёт Supabase Auth session — запросы идут как anon.
-- Без GRANT anon сохранение чеклистов (RPC save_checklist) не работает.
GRANT EXECUTE ON FUNCTION public.save_checklist TO anon;
