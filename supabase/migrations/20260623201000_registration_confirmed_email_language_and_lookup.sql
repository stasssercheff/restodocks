-- Письмо registration_confirmed: находить сотрудника и по auth_user_id, передавать язык в Edge (тема/текст).

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
  func_url text := 'https://osglfptwbuqqmqunttha.supabase.co/functions/v1/send-registration-email';
  v_lang text;
BEGIN
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
