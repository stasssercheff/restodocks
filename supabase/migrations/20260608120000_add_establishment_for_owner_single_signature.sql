-- PGRST203: две перегрузки add_establishment_for_owner(5 и 6 аргументов) — PostgREST не выбирает кандидата.
DROP FUNCTION IF EXISTS public.add_establishment_for_owner(text, text, text, text, text);

-- Одна сигнатура с default NULL на последнем аргументе; подписка и промо — как у «эталонного» заведения владельца.
CREATE OR REPLACE FUNCTION public.add_establishment_for_owner(
  p_name text,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_pin_code text DEFAULT NULL,
  p_parent_establishment_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid;
  v_pin text;
  v_est jsonb;
  v_new_id uuid;
  v_now timestamptz := now();
  v_current_count int;
  v_max int;
  v_template_id uuid;
  v_sub text;
  v_trial timestamptz;
  v_paid timestamptz;
BEGIN
  v_owner_id := auth.uid();
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'add_establishment_for_owner: must be authenticated';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM establishments WHERE owner_id = v_owner_id) THEN
    RAISE EXCEPTION 'add_establishment_for_owner: only owners can add establishments';
  END IF;

  SELECT COUNT(*)::int INTO v_current_count
  FROM establishments WHERE owner_id = v_owner_id;

  -- Лимит доп. заведений: без Pro у владельца — 0; с Pro — min(2, эффективный лимит платформы/админки).
  IF public.owner_has_paid_pro_entitlement(v_owner_id) THEN
    v_max := LEAST(
      2,
      public.get_effective_max_additional_establishments_for_owner()
    );
  ELSE
    v_max := LEAST(
      0,
      public.get_effective_max_additional_establishments_for_owner()
    );
  END IF;

  IF (v_current_count - 1) >= v_max THEN
    RAISE EXCEPTION 'add_establishment_for_owner: limit reached, max % additional establishments per owner', v_max;
  END IF;

  IF p_parent_establishment_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM establishments
      WHERE id = p_parent_establishment_id
        AND owner_id = v_owner_id
        AND parent_establishment_id IS NULL
    ) THEN
      RAISE EXCEPTION 'add_establishment_for_owner: parent must be your main establishment';
    END IF;
    v_template_id := p_parent_establishment_id;
  ELSE
    SELECT e.id INTO v_template_id
    FROM establishments e
    WHERE e.owner_id = v_owner_id
    ORDER BY e.created_at ASC
    LIMIT 1;
  END IF;

  SELECT
    lower(trim(COALESCE(subscription_type, 'free'))),
    pro_trial_ends_at,
    pro_paid_until
  INTO v_sub, v_trial, v_paid
  FROM establishments
  WHERE id = v_template_id;

  IF p_pin_code IS NULL OR trim(p_pin_code) = '' THEN
    LOOP
      v_pin := upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 6));
      IF NOT EXISTS (SELECT 1 FROM establishments WHERE pin_code = v_pin) THEN
        EXIT;
      END IF;
    END LOOP;
  ELSE
    v_pin := upper(trim(p_pin_code));
    IF EXISTS (SELECT 1 FROM establishments WHERE pin_code = v_pin) THEN
      RAISE EXCEPTION 'add_establishment_for_owner: pin_code already exists';
    END IF;
  END IF;

  INSERT INTO establishments (
    name,
    pin_code,
    owner_id,
    address,
    phone,
    email,
    parent_establishment_id,
    subscription_type,
    pro_trial_ends_at,
    pro_paid_until,
    created_at,
    updated_at
  )
  VALUES (
    trim(p_name),
    v_pin,
    v_owner_id,
    nullif(trim(p_address), ''),
    nullif(trim(p_phone), ''),
    nullif(trim(p_email), ''),
    p_parent_establishment_id,
    NULLIF(trim(COALESCE(v_sub, '')), ''),
    v_trial,
    v_paid,
    v_now,
    v_now
  )
  RETURNING id INTO v_new_id;

  SELECT to_jsonb(e.*) INTO v_est FROM public.establishments e WHERE e.id = v_new_id;

  -- Второе заведение на тот же промокод (до 2 на код) — чтобы Pro по промо действовал и на филиал/новое.
  INSERT INTO public.promo_code_redemptions (promo_code_id, establishment_id, redeemed_at)
  SELECT r.promo_code_id, v_new_id, r.redeemed_at
  FROM public.promo_code_redemptions r
  WHERE r.establishment_id = v_template_id
    AND (
      SELECT COUNT(*)::int
      FROM public.promo_code_redemptions c
      WHERE c.promo_code_id = r.promo_code_id
    ) < 2
  ON CONFLICT (establishment_id) DO NOTHING;

  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION public.add_establishment_for_owner(text, text, text, text, text, uuid) IS
  'Добавление заведения владельцем; лимит по Pro владельца; подписка и погашение промо копируются с основы/шаблона.';

GRANT EXECUTE ON FUNCTION public.add_establishment_for_owner(text, text, text, text, text, uuid) TO authenticated;
