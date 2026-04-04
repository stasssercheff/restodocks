-- Доступ техподдержки: владелец включает флаг; оператор платформы ищет заведение по PIN через RPC.

ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS support_access_enabled boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.establishments.support_access_enabled IS
  'Если true — оператор платформы может найти заведение по PIN в админке (после согласия владельца).';

CREATE TABLE IF NOT EXISTS public.platform_support_operators (
  email text PRIMARY KEY
);

COMMENT ON TABLE public.platform_support_operators IS
  'Email-ы аккаунтов, которым разрешён вызов support_lookup_establishment_by_pin. Пополняется вручную (SQL).';

INSERT INTO public.platform_support_operators (email)
VALUES ('stasssercheff@gmail.com')
ON CONFLICT (email) DO NOTHING;

ALTER TABLE public.platform_support_operators ENABLE ROW LEVEL SECURITY;

-- Только service role обходит RLS; authenticated не видит таблицу без политик.

CREATE OR REPLACE FUNCTION public.support_lookup_establishment_by_pin(p_pin text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text;
  v_row public.establishments%ROWTYPE;
  v_employees jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT u.email::text INTO v_email FROM auth.users u WHERE u.id = auth.uid();
  IF v_email IS NULL OR length(trim(v_email)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.platform_support_operators o
    WHERE lower(trim(o.email)) = lower(trim(v_email))
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'forbidden');
  END IF;

  IF p_pin IS NULL OR length(trim(p_pin)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_pin');
  END IF;

  SELECT * INTO v_row
  FROM public.establishments e
  WHERE upper(trim(e.pin_code)) = upper(trim(p_pin))
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  IF NOT coalesce(v_row.support_access_enabled, false) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'support_disabled');
  END IF;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', e.id,
        'full_name', e.full_name,
        'surname', e.surname,
        'email', e.email,
        'roles', e.roles,
        'is_active', e.is_active
      )
      ORDER BY e.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_employees
  FROM public.employees e
  WHERE e.establishment_id = v_row.id;

  RETURN jsonb_build_object(
    'ok', true,
    'establishment', jsonb_build_object(
      'id', v_row.id,
      'name', v_row.name,
      'pin_code', v_row.pin_code,
      'owner_id', v_row.owner_id,
      'support_access_enabled', v_row.support_access_enabled
    ),
    'employees', coalesce(v_employees, '[]'::jsonb)
  );
END;
$$;

COMMENT ON FUNCTION public.support_lookup_establishment_by_pin(text) IS
  'Оператор платформы: по PIN заведения возвращает карточку и сотрудников, если включён support_access_enabled.';

GRANT EXECUTE ON FUNCTION public.support_lookup_establishment_by_pin(text) TO authenticated;
