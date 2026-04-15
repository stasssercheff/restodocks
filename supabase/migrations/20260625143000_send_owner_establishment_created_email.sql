-- Письмо владельцу при создании заведения (каждое новое заведение + PIN).
-- Отправка из БД, чтобы не зависеть от клиентских 4xx при owner-first потоке.

CREATE OR REPLACE FUNCTION public.send_owner_establishment_created_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_to text;
  v_lang text;
  v_full_name text;
  anon_key text;
  func_url text;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RETURN NEW;
  END IF;

  IF NEW.owner_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO func_url
  FROM vault.decrypted_secrets
  WHERE name = 'edge_send_registration_email_url'
  LIMIT 1;

  IF func_url IS NULL OR btrim(func_url) = '' THEN
    func_url := 'https://osglfptwbuqqmqunttha.supabase.co/functions/v1/send-registration-email';
  END IF;

  SELECT u.email,
         lower(trim(COALESCE(u.raw_user_meta_data->>'interface_language', 'en')))
  INTO v_to, v_lang
  FROM auth.users u
  WHERE u.id = NEW.owner_id
  LIMIT 1;

  IF v_lang IS NULL OR v_lang = '' THEN
    v_lang := 'en';
  END IF;

  IF v_to IS NULL OR btrim(v_to) = '' THEN
    RETURN NEW;
  END IF;

  SELECT e.full_name INTO v_full_name
  FROM public.employees e
  WHERE e.id = NEW.owner_id OR e.auth_user_id = NEW.owner_id
  ORDER BY e.updated_at DESC NULLS LAST
  LIMIT 1;

  IF v_full_name IS NULL OR btrim(v_full_name) = '' THEN
    SELECT por.full_name INTO v_full_name
    FROM public.pending_owner_registrations por
    WHERE por.auth_user_id = NEW.owner_id
    ORDER BY por.updated_at DESC NULLS LAST
    LIMIT 1;
  END IF;

  SELECT decrypted_secret INTO anon_key
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_anon_key'
  LIMIT 1;

  IF anon_key IS NULL OR anon_key = '' THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := func_url,
    body := jsonb_build_object(
      'type', 'owner',
      'to', v_to,
      'companyName', COALESCE(NEW.name, ''),
      'email', v_to,
      'fullName', COALESCE(v_full_name, ''),
      'pinCode', COALESCE(NEW.pin_code, ''),
      'language', v_lang
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || anon_key
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_establishment_created_send_owner_email ON public.establishments;
CREATE TRIGGER on_establishment_created_send_owner_email
  AFTER INSERT ON public.establishments
  FOR EACH ROW
  EXECUTE FUNCTION public.send_owner_establishment_created_email();

COMMENT ON FUNCTION public.send_owner_establishment_created_email() IS
  'После INSERT в establishments отправляет владельцу письмо owner (PIN + логин) через Edge send-registration-email.';
