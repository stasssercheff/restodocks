-- Письмо о завершении регистрации при подтверждении email (auth.users.email_confirmed_at)
-- Требуется: pg_net, vault с supabase_anon_key
-- Добавьте anon key в vault один раз: SELECT vault.create_secret('ВАШ_ANON_KEY', 'supabase_anon_key', 'Edge Function auth');

CREATE EXTENSION IF NOT EXISTS pg_net;

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
BEGIN
  -- Только когда email_confirmed_at меняется с NULL на не-NULL
  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL AND NEW.email IS NOT NULL THEN
    -- Данные сотрудника и заведения
    SELECT e.email, est.name INTO emp_email, est_name
    FROM public.employees e
    LEFT JOIN public.establishments est ON est.id = e.establishment_id
    WHERE e.auth_user_id = NEW.id
    LIMIT 1;

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
            'companyName', COALESCE(est_name, '')
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

DROP TRIGGER IF EXISTS on_auth_user_email_confirmed ON auth.users;
CREATE TRIGGER on_auth_user_email_confirmed
  AFTER UPDATE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.send_registration_confirmed_email();
