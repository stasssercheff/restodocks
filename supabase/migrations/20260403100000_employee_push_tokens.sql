-- FCM/APNs токены устройств для фоновых push (сервер шлёт через Edge Function).
CREATE TABLE IF NOT EXISTS public.employee_push_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'unknown',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT employee_push_tokens_fcm_token_unique UNIQUE (fcm_token)
);

CREATE INDEX IF NOT EXISTS idx_employee_push_tokens_employee_id
  ON public.employee_push_tokens(employee_id);

COMMENT ON TABLE public.employee_push_tokens IS 'FCM registration tokens; отправка push через Edge Function (firebase-admin).';

ALTER TABLE public.employee_push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS employee_push_tokens_own ON public.employee_push_tokens;
CREATE POLICY employee_push_tokens_own ON public.employee_push_tokens
  FOR ALL TO authenticated
  USING (employee_id = auth.uid())
  WITH CHECK (employee_id = auth.uid());

-- Регистрация токена с клиента (JWT sub = id сотрудника).
CREATE OR REPLACE FUNCTION public.register_push_token(p_fcm_token text, p_platform text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  t text := trim(coalesce(p_fcm_token, ''));
  pl text := lower(trim(coalesce(p_platform, '')));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'register_push_token: not authenticated';
  END IF;
  IF length(t) < 20 THEN
    RAISE EXCEPTION 'register_push_token: invalid token';
  END IF;
  IF pl NOT IN ('ios', 'android', 'web', 'macos', 'unknown') THEN
    pl := 'unknown';
  END IF;
  INSERT INTO public.employee_push_tokens (employee_id, fcm_token, platform, updated_at)
  VALUES (auth.uid(), t, pl, now())
  ON CONFLICT (fcm_token) DO UPDATE SET
    employee_id = excluded.employee_id,
    platform = excluded.platform,
    updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_push_token(p_fcm_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  t text := trim(coalesce(p_fcm_token, ''));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unregister_push_token: not authenticated';
  END IF;
  DELETE FROM public.employee_push_tokens
  WHERE fcm_token = t AND employee_id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.register_push_token(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_push_token(text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.unregister_push_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.unregister_push_token(text) TO authenticated;
