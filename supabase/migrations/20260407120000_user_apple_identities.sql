-- Привязка Sign in with Apple (стабильный идентификатор пользователя для приложения) к auth.users.
-- Политика: один apple_sub → один аккаунт Restodocks (проверка на клиенте + RPC при регистрации).

CREATE TABLE IF NOT EXISTS public.user_apple_identities (
  apple_sub text PRIMARY KEY,
  auth_user_id uuid NOT NULL UNIQUE REFERENCES auth.users (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.user_apple_identities IS
  'Идентификатор Apple ID для приложения (credential.user) ↔ один пользователь Supabase Auth.';

ALTER TABLE public.user_apple_identities ENABLE ROW LEVEL SECURITY;

-- Прямой доступ запрещён; только через SECURITY DEFINER RPC.

CREATE OR REPLACE FUNCTION public.is_apple_sub_registered(p_apple_sub text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_apple_identities
    WHERE apple_sub = trim(p_apple_sub)
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_apple_sub_registered(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.link_apple_sub_to_current_user(p_apple_sub text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_trim text := trim(p_apple_sub);
  v_existing uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF v_trim IS NULL OR v_trim = '' THEN
    RAISE EXCEPTION 'invalid apple_sub';
  END IF;

  SELECT auth_user_id INTO v_existing
  FROM public.user_apple_identities
  WHERE apple_sub = v_trim;

  IF v_existing IS NULL THEN
    INSERT INTO public.user_apple_identities (apple_sub, auth_user_id)
    VALUES (v_trim, v_uid);
    RETURN jsonb_build_object('ok', true, 'linked', true);
  END IF;

  IF v_existing = v_uid THEN
    RETURN jsonb_build_object('ok', true, 'linked', false);
  END IF;

  RAISE EXCEPTION 'APPLE_SUB_ALREADY_LINKED';
END;
$$;

GRANT EXECUTE ON FUNCTION public.link_apple_sub_to_current_user(text) TO authenticated;

COMMENT ON FUNCTION public.is_apple_sub_registered(text) IS
  'До регистрации: занят ли уже этот Apple-идентификатор в Restodocks.';
COMMENT ON FUNCTION public.link_apple_sub_to_current_user(text) IS
  'После входа: сохранить привязку Apple ID к текущему auth.uid().';
