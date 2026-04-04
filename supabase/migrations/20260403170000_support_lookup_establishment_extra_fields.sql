-- Расширение ответа support_lookup_establishment_by_pin: реквизиты заведения для админки поддержки.

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
      'support_access_enabled', v_row.support_access_enabled,
      'address', v_row.address,
      'phone', v_row.phone,
      'email', v_row.email,
      'default_currency', v_row.default_currency,
      'subscription_type', v_row.subscription_type,
      'pro_trial_ends_at', v_row.pro_trial_ends_at,
      'pro_paid_until', v_row.pro_paid_until,
      'parent_establishment_id', v_row.parent_establishment_id
    ),
    'employees', coalesce(v_employees, '[]'::jsonb)
  );
END;
$$;

COMMENT ON FUNCTION public.support_lookup_establishment_by_pin(text) IS
  'Оператор платформы: по PIN заведения — карточка, реквизиты и сотрудники при support_access_enabled.';
