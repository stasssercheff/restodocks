-- Исправление: auth user есть и подтверждён, но нет employee — создать владельца
-- Выполнить в Supabase Dashboard → SQL Editor
-- Подставьте свой email в последней строке

DO $$
DECLARE
  v_email text := 'rebrikov.st@gmail.com';  -- <-- ВАШ EMAIL
  v_est_id uuid;
  v_auth_id uuid;
  v_name text;
BEGIN
  SELECT id INTO v_auth_id FROM auth.users 
  WHERE LOWER(email) = LOWER(v_email) AND email_confirmed_at IS NOT NULL
  LIMIT 1;
  
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'Auth user с email % не найден или email не подтверждён', v_email;
  END IF;

  IF EXISTS (SELECT 1 FROM employees WHERE id = v_auth_id) THEN
    RAISE NOTICE 'Employee уже существует для %', v_email;
    RETURN;
  END IF;

  SELECT id INTO v_est_id FROM establishments WHERE owner_id IS NULL ORDER BY created_at DESC LIMIT 1;
  IF v_est_id IS NULL THEN
    RAISE EXCEPTION 'Нет заведения без владельца. Сначала создайте компанию или укажите establishment_id';
  END IF;

  v_name := COALESCE((SELECT raw_user_meta_data->>'full_name' FROM auth.users WHERE id = v_auth_id), split_part(v_email, '@', 1));

  INSERT INTO employees (id, full_name, surname, email, password_hash, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, created_at, updated_at)
  VALUES (v_auth_id, v_name, NULL, v_email, NULL, 'management', NULL, ARRAY['owner'], v_est_id,
    lpad((floor(random() * 900000) + 100000)::text, 6, '0'), 'ru', true, now(), now());

  UPDATE establishments SET owner_id = v_auth_id, updated_at = now() WHERE id = v_est_id;

  RAISE NOTICE 'Создан employee для %, establishment_id = %', v_email, v_est_id;
END $$;
