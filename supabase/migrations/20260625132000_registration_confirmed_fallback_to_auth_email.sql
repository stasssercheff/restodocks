-- registration_confirmed: если employee ещё не создан (owner-first до шага компании),
-- отправлять письмо на NEW.email из auth.users.

CREATE OR REPLACE FUNCTION public.send_registration_confirmed_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  emp_email text;
  emp_full_name text;
  pending_full_name text;
  pending_email text;
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
    SELECT e.email, e.full_name, est.name
    INTO emp_email, emp_full_name, est_name
    FROM public.employees e
    LEFT JOIN public.establishments est ON est.id = e.establishment_id
    WHERE e.id = NEW.id OR e.auth_user_id = NEW.id
    LIMIT 1;

    SELECT por.full_name, por.email
    INTO pending_full_name, pending_email
    FROM public.pending_owner_registrations por
    WHERE por.auth_user_id = NEW.id
    ORDER BY por.updated_at DESC NULLS LAST
    LIMIT 1;

    -- owner-first до создания компании: employee может отсутствовать.
    IF emp_email IS NULL OR btrim(emp_email) = '' THEN
      emp_email := COALESCE(pending_email, NEW.email);
    END IF;

    v_lang := lower(trim(COALESCE(NEW.raw_user_meta_data->>'interface_language', 'en')));
    IF v_lang IS NULL OR v_lang = '' THEN
      v_lang := 'en';
    END IF;

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
          'fullName', COALESCE(emp_full_name, pending_full_name, ''),
          'email', COALESCE(emp_email, NEW.email, ''),
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

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.send_registration_confirmed_email() IS
  'После подтверждения email вызывает Edge send-registration-email (registration_confirmed). Если employee ещё не создан — fallback на auth.users.email.';
