-- Однократно прогоняет check_establishment_access по всем заведениям:
-- снимает платный subscription_type, если нет IAP и нет действующего промо
-- (старые строки могли «залипнуть», пока RPC не вызывался или отвечал 400).

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id FROM public.establishments
  LOOP
    PERFORM public.check_establishment_access(r.id);
  END LOOP;
END;
$$;
