-- send_registration_confirmed_email: URL Edge читать из Vault (один раз настроить в Dashboard),
-- иначе запасной URL проекта из репозитория.
--
-- Опционально в SQL Editor (один раз):
--   SELECT vault.create_secret(
--     'https://<PROJECT_REF>.supabase.co/functions/v1/send-registration-email',
--     'edge_send_registration_email_url',
--     'Полный URL Edge send-registration-email для триггера auth.users'
--   );
-- Как и раньше нужны: pg_net, секрет supabase_anon_key, триггер on_auth_user_email_confirmed.

CREATE OR REPLACE FUNCTION public.send_registration_confirmed_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  emp_email text;
  est_name text;
  anon_key text;
  func_url text;
  v_lang text;
BEGIN
  SELECT decrypted_secret INTO func_url
  FROM vault.decrypted_secrets
  WHERE name = 'edge_send_registration_email_url'
  LIMIT 1;

  IF func_url IS NULL OR btrim(func_url) = '' THEN
    func_url := 'https://osglfptwbuqqmqunttha.supabase.co/functions/v1/send-registration-email';
  END IF;

  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL AND NEW.email IS NOT NULL THEN
    SELECT e.email, est.name
    INTO emp_email, est_name
    FROM public.employees e
    LEFT JOIN public.establishments est ON est.id = e.establishment_id
    WHERE e.id = NEW.id OR e.auth_user_id = NEW.id
    LIMIT 1;

    v_lang := lower(trim(COALESCE(NEW.raw_user_meta_data->>'interface_language', 'en')));
    IF v_lang IS NULL OR v_lang = '' THEN
      v_lang := 'en';
    END IF;

    IF emp_email IS NOT NULL THEN
      SELECT decrypted_secret INTO anon_key
      FROM vault.decrypted_secrets
      WHERE name = 'supabase_anon_key'
      LIMIT 1;

      IF anon_key IS NOT NULL AND anon_key != '' THEN
        PERFORM net.http_post(
          url := func_url,
          body := jsonb_build_object(
            'type', 'registration_confirmed',
            'to', emp_email,
            'companyName', COALESCE(est_name, ''),
            'language', v_lang
          ),
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || anon_key
          )
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.send_registration_confirmed_email() IS
  'После подтверждения email вызывает Edge send-registration-email (registration_confirmed). URL: vault.edge_send_registration_email_url или дефолт проекта; Authorization: vault.supabase_anon_key.';
