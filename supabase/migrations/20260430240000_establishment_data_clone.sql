-- Копирование данных между заведениями одного владельца: заявка → письмо со ссылкой → подтверждение → INSERT в целевое заведение.
-- Не меняет существующие RPC регистрации/входа.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Доп. колонки (если старая БД)
ALTER TABLE tt_ingredients ADD COLUMN IF NOT EXISTS manual_effective_gross REAL;
ALTER TABLE tt_ingredients ADD COLUMN IF NOT EXISTS price_per_kg REAL;
ALTER TABLE tt_ingredients ADD COLUMN IF NOT EXISTS cost_currency TEXT;
ALTER TABLE tech_cards ADD COLUMN IF NOT EXISTS is_semi_finished BOOLEAN DEFAULT true;
ALTER TABLE tech_cards ADD COLUMN IF NOT EXISTS technology_localized JSONB;
ALTER TABLE tech_cards ADD COLUMN IF NOT EXISTS sections JSONB NOT NULL DEFAULT '[]'::jsonb;

CREATE TABLE IF NOT EXISTS public.establishment_data_clone_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  source_establishment_id UUID NOT NULL REFERENCES public.establishments (id) ON DELETE CASCADE,
  target_establishment_id UUID NOT NULL REFERENCES public.establishments (id) ON DELETE CASCADE,
  options JSONB NOT NULL DEFAULT '{}'::jsonb,
  token_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  applied_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_establishment_data_clone_token_hash
  ON public.establishment_data_clone_requests (token_hash)
  WHERE applied_at IS NULL;

COMMENT ON TABLE public.establishment_data_clone_requests IS 'Одноразовая заявка на копирование номенклатуры/ТТК между заведениями; подтверждение по токену из письма.';

ALTER TABLE public.establishment_data_clone_requests DISABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.establishment_data_clone_requests FROM PUBLIC;

-- Внутренняя копия (SECURITY DEFINER)
CREATE OR REPLACE FUNCTION public._perform_establishment_data_clone(
  p_source_data_establishment_id UUID,
  p_target_establishment_id UUID,
  p_options JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nom BOOLEAN := COALESCE((p_options->>'nomenclature')::boolean, true);
  v_ttk BOOLEAN := COALESCE((p_options->>'tech_cards')::boolean, true);
  v_ord BOOLEAN := COALESCE((p_options->>'order_lists')::boolean, false);
BEGIN
  IF v_nom THEN
    INSERT INTO public.establishment_products (
      id, establishment_id, product_id, price, currency, department
    )
    SELECT gen_random_uuid(), p_target_establishment_id, ep.product_id, ep.price, ep.currency, ep.department
    FROM public.establishment_products ep
    WHERE ep.establishment_id = p_source_data_establishment_id
    ON CONFLICT ON CONSTRAINT establishment_products_est_product_dept_key DO NOTHING;
  END IF;

  IF v_ord THEN
    INSERT INTO public.establishment_order_list_data (id, establishment_id, data, updated_at)
    SELECT gen_random_uuid(), p_target_establishment_id, s.data, now()
    FROM public.establishment_order_list_data s
    WHERE s.establishment_id = p_source_data_establishment_id
    ON CONFLICT (establishment_id) DO UPDATE SET
      data = EXCLUDED.data,
      updated_at = now();
  END IF;

  IF NOT v_ttk THEN
    RETURN;
  END IF;

  CREATE TEMP TABLE _clone_cat_map (old_uuid UUID PRIMARY KEY, new_uuid UUID NOT NULL) ON COMMIT DROP;
  CREATE TEMP TABLE _clone_tc_map (old_uuid UUID PRIMARY KEY, new_uuid UUID NOT NULL) ON COMMIT DROP;

  INSERT INTO _clone_cat_map (old_uuid, new_uuid)
  SELECT c.id, gen_random_uuid()
  FROM public.tech_card_custom_categories c
  WHERE c.establishment_id = p_source_data_establishment_id;

  INSERT INTO public.tech_card_custom_categories (id, establishment_id, name, department, created_at)
  SELECT m.new_uuid, p_target_establishment_id, c.name, c.department, now()
  FROM public.tech_card_custom_categories c
  JOIN _clone_cat_map m ON m.old_uuid = c.id;

  INSERT INTO _clone_tc_map (old_uuid, new_uuid)
  SELECT tc.id, gen_random_uuid()
  FROM public.tech_cards tc
  WHERE tc.establishment_id = p_source_data_establishment_id;

  INSERT INTO public.tech_cards (
    id,
    dish_name,
    dish_name_localized,
    category,
    portion_weight,
    yield,
    technology,
    comment,
    card_type,
    base_portions,
    establishment_id,
    created_by,
    photo_urls,
    created_at,
    updated_at,
    sections,
    department,
    is_semi_finished,
    technology_localized,
    description_for_hall,
    composition_for_hall,
    selling_price
  )
  SELECT
    m.new_uuid,
    tc.dish_name,
    tc.dish_name_localized,
    CASE
      WHEN tc.category LIKE 'custom:%' AND split_part(tc.category, ':', 2) ~ '^[0-9a-fA-F-]{36}$' THEN
        CASE
          WHEN EXISTS (
            SELECT 1 FROM _clone_cat_map cm
            WHERE cm.old_uuid = split_part(tc.category, ':', 2)::uuid
          )
          THEN 'custom:' || (
            SELECT cm2.new_uuid::text FROM _clone_cat_map cm2
            WHERE cm2.old_uuid = split_part(tc.category, ':', 2)::uuid
          )
          ELSE tc.category
        END
      ELSE tc.category
    END,
    tc.portion_weight,
    tc.yield,
    tc.technology,
    tc.comment,
    tc.card_type,
    tc.base_portions,
    p_target_establishment_id,
    tc.created_by,
    tc.photo_urls,
    now(),
    now(),
    COALESCE(tc.sections, '[]'::jsonb),
    COALESCE(tc.department, 'kitchen'),
    COALESCE(tc.is_semi_finished, true),
    tc.technology_localized,
    tc.description_for_hall,
    tc.composition_for_hall,
    tc.selling_price
  FROM public.tech_cards tc
  JOIN _clone_tc_map m ON m.old_uuid = tc.id;

  INSERT INTO public.tt_ingredients (
    id,
    product_id,
    product_name,
    source_tech_card_id,
    source_tech_card_name,
    cooking_process_id,
    cooking_process_name,
    gross_weight,
    net_weight,
    is_net_weight_manual,
    final_calories,
    final_protein,
    final_fat,
    final_carbs,
    cost,
    tech_card_id,
    created_at,
    unit,
    primary_waste_pct,
    grams_per_piece,
    cooking_loss_pct_override,
    output_weight,
    manual_effective_gross,
    price_per_kg,
    cost_currency
  )
  SELECT
    gen_random_uuid(),
    ti.product_id,
    ti.product_name,
    CASE WHEN ti.source_tech_card_id IS NOT NULL THEN sm.new_uuid ELSE NULL END,
    ti.source_tech_card_name,
    ti.cooking_process_id,
    ti.cooking_process_name,
    ti.gross_weight,
    ti.net_weight,
    ti.is_net_weight_manual,
    ti.final_calories,
    ti.final_protein,
    ti.final_fat,
    ti.final_carbs,
    ti.cost,
    m.new_uuid,
    now(),
    COALESCE(ti.unit, 'g'),
    COALESCE(ti.primary_waste_pct, 0),
    ti.grams_per_piece,
    ti.cooking_loss_pct_override,
    COALESCE(ti.output_weight, 0),
    ti.manual_effective_gross,
    ti.price_per_kg,
    ti.cost_currency
  FROM public.tt_ingredients ti
  JOIN _clone_tc_map m ON m.old_uuid = ti.tech_card_id
  LEFT JOIN _clone_tc_map sm ON sm.old_uuid = ti.source_tech_card_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.request_establishment_data_clone(
  p_source_establishment_id UUID,
  p_target_establishment_id UUID,
  p_source_pin TEXT,
  p_target_pin TEXT,
  p_options JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner UUID := auth.uid();
  v_src_pin TEXT;
  v_tgt_pin TEXT;
  v_src_owner UUID;
  v_tgt_owner UUID;
  v_token BYTEA;
  v_token_hex TEXT;
  v_hash TEXT;
  v_exp TIMESTAMPTZ := now() + interval '48 hours';
  v_id UUID;
BEGIN
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'request_establishment_data_clone: not authenticated';
  END IF;

  IF p_source_establishment_id = p_target_establishment_id THEN
    RAISE EXCEPTION 'request_establishment_data_clone: source and target must differ';
  END IF;

  SELECT e.owner_id, upper(trim(e.pin_code))
  INTO v_src_owner, v_src_pin
  FROM public.establishments e
  WHERE e.id = p_source_establishment_id;

  SELECT e.owner_id, upper(trim(e.pin_code))
  INTO v_tgt_owner, v_tgt_pin
  FROM public.establishments e
  WHERE e.id = p_target_establishment_id;

  IF v_src_owner IS NULL OR v_tgt_owner IS NULL THEN
    RAISE EXCEPTION 'request_establishment_data_clone: establishment not found';
  END IF;

  IF v_src_owner <> v_owner OR v_tgt_owner <> v_owner THEN
    RAISE EXCEPTION 'request_establishment_data_clone: not owner of both establishments';
  END IF;

  IF v_src_pin <> upper(trim(p_source_pin)) OR v_tgt_pin <> upper(trim(p_target_pin)) THEN
    RAISE EXCEPTION 'request_establishment_data_clone: invalid pin';
  END IF;

  v_token := gen_random_bytes(32);
  v_token_hex := encode(v_token, 'hex');
  v_hash := encode(digest(v_token, 'sha256'), 'hex');

  INSERT INTO public.establishment_data_clone_requests (
    owner_id,
    source_establishment_id,
    target_establishment_id,
    options,
    token_hash,
    expires_at
  ) VALUES (
    v_owner,
    p_source_establishment_id,
    p_target_establishment_id,
    COALESCE(p_options, '{}'::jsonb),
    v_hash,
    v_exp
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'request_id', v_id,
    'token', v_token_hex,
    'expires_at', v_exp
  );
END;
$$;

COMMENT ON FUNCTION public.request_establishment_data_clone IS 'Создать заявку на копирование; вернуть одноразовый token для ссылки в письме.';

CREATE OR REPLACE FUNCTION public.confirm_establishment_data_clone(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hash TEXT;
  v_row public.establishment_data_clone_requests%ROWTYPE;
  v_src_data UUID;
BEGIN
  IF p_token IS NULL OR length(trim(p_token)) < 32 THEN
    RAISE EXCEPTION 'confirm_establishment_data_clone: invalid token';
  END IF;

  v_hash := encode(digest(decode(trim(p_token), 'hex'), 'sha256'), 'hex');

  SELECT * INTO v_row
  FROM public.establishment_data_clone_requests r
  WHERE r.token_hash = v_hash
    AND r.applied_at IS NULL
    AND r.expires_at > now()
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'confirm_establishment_data_clone: token expired or already used';
  END IF;

  v_src_data := public.get_data_establishment_id(v_row.source_establishment_id);

  PERFORM public._perform_establishment_data_clone(
    v_src_data,
    v_row.target_establishment_id,
    v_row.options
  );

  UPDATE public.establishment_data_clone_requests
  SET applied_at = now()
  WHERE id = v_row.id;

  RETURN jsonb_build_object('ok', true, 'target_establishment_id', v_row.target_establishment_id);
END;
$$;

COMMENT ON FUNCTION public.confirm_establishment_data_clone IS 'Подтвердить копирование по токену из письма (можно без сессии).';

GRANT EXECUTE ON FUNCTION public.request_establishment_data_clone(UUID, UUID, TEXT, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_establishment_data_clone(TEXT) TO anon, authenticated;
