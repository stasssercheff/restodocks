-- Однократно прогоняет check_establishment_access по всем заведениям:
-- снимает платный subscription_type, если нет IAP и нет действующего промо
-- (старые строки могли «залипнуть», пока RPC не вызывался или отвечал 400).
--
-- Если ERROR 42703 про promo_codes.activation_duration_days — сначала выполни
-- 20260621140000_ensure_promo_codes_activation_duration_days.sql (или полную 20260609120000).

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
