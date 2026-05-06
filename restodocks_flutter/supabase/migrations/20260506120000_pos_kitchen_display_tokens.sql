-- Внешний доступ к KDS: долгоживущий токен (без входа в учётку), только заказы + ТТК + «отдано».
-- Данные при закрытой смене не отдаются, если у токена require_active_shift = true.

CREATE TABLE IF NOT EXISTS public.pos_kitchen_display_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES public.establishments (id) ON DELETE CASCADE,
  token text NOT NULL UNIQUE,
  department text NOT NULL CHECK (department IN ('kitchen', 'bar')),
  require_active_shift boolean NOT NULL DEFAULT true,
  label text,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);

CREATE INDEX IF NOT EXISTS pos_kitchen_display_tokens_token_active_idx
  ON public.pos_kitchen_display_tokens (token)
  WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS pos_kitchen_display_tokens_est_idx
  ON public.pos_kitchen_display_tokens (establishment_id);

ALTER TABLE public.pos_kitchen_display_tokens ENABLE ROW LEVEL SECURITY;

-- Управление токенами: владелец, ген. директор или менеджер зала.
CREATE POLICY pos_kds_tokens_select ON public.pos_kitchen_display_tokens
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.employees emp
      WHERE emp.auth_user_id = auth.uid()
        AND emp.is_active = true
        AND emp.establishment_id = pos_kitchen_display_tokens.establishment_id
        AND (
          'owner' = ANY (emp.roles)
          OR 'general_manager' = ANY (emp.roles)
          OR (
            emp.department IN ('hall', 'dining_room')
            AND 'floor_manager' = ANY (emp.roles)
          )
        )
    )
  );

CREATE POLICY pos_kds_tokens_insert ON public.pos_kitchen_display_tokens
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.employees emp
      WHERE emp.auth_user_id = auth.uid()
        AND emp.is_active = true
        AND emp.establishment_id = pos_kitchen_display_tokens.establishment_id
        AND (
          'owner' = ANY (emp.roles)
          OR 'general_manager' = ANY (emp.roles)
          OR (
            emp.department IN ('hall', 'dining_room')
            AND 'floor_manager' = ANY (emp.roles)
          )
        )
    )
  );

CREATE POLICY pos_kds_tokens_update ON public.pos_kitchen_display_tokens
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.employees emp
      WHERE emp.auth_user_id = auth.uid()
        AND emp.is_active = true
        AND emp.establishment_id = pos_kitchen_display_tokens.establishment_id
        AND (
          'owner' = ANY (emp.roles)
          OR 'general_manager' = ANY (emp.roles)
          OR (
            emp.department IN ('hall', 'dining_room')
            AND 'floor_manager' = ANY (emp.roles)
          )
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.employees emp
      WHERE emp.auth_user_id = auth.uid()
        AND emp.is_active = true
        AND emp.establishment_id = pos_kitchen_display_tokens.establishment_id
        AND (
          'owner' = ANY (emp.roles)
          OR 'general_manager' = ANY (emp.roles)
          OR (
            emp.department IN ('hall', 'dining_room')
            AND 'floor_manager' = ANY (emp.roles)
          )
        )
    )
  );

CREATE OR REPLACE FUNCTION public._pos_kds_line_is_bar(p_category text, p_sections jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT coalesce(lower(trim(p_category)), '') IN (
    'beverages',
    'alcoholic_cocktails',
    'non_alcoholic_drinks',
    'hot_drinks',
    'drinks_pure',
    'snacks'
  )
  OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements_text(coalesce(p_sections, '[]'::jsonb)) AS e(t)
    WHERE e.t = 'bar'
  );
$$;

CREATE OR REPLACE FUNCTION public.pos_kds_fetch_orders(p_token text, p_department text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_t public.pos_kitchen_display_tokens%ROWTYPE;
  v_shift_open boolean;
  o record;
  v_lines jsonb;
  v_menu_subtotal numeric;
  v_partial boolean;
  v_all_served boolean;
  v_bucket text;
  v_grand numeric;
  v_order jsonb;
  v_orders_accum jsonb := '[]'::jsonb;
  v_d text;
BEGIN
  v_d := lower(trim(coalesce(p_department, '')));
  IF v_d NOT IN ('kitchen', 'bar') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_department');
  END IF;

  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  SELECT * INTO v_t
  FROM public.pos_kitchen_display_tokens
  WHERE token = trim(p_token)
    AND revoked_at IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  IF v_t.department IS DISTINCT FROM v_d THEN
    RETURN jsonb_build_object('ok', false, 'error', 'department_mismatch');
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.pos_cash_shifts s
    WHERE s.establishment_id = v_t.establishment_id
      AND s.ended_at IS NULL
  )
  INTO v_shift_open;

  IF v_t.require_active_shift AND NOT coalesce(v_shift_open, false) THEN
    RETURN jsonb_build_object(
      'ok', true,
      'shift_required', true,
      'shift_open', false,
      'department', v_t.department,
      'establishment_id', v_t.establishment_id,
      'orders', '[]'::jsonb
    );
  END IF;

  FOR o IN
    SELECT
      po.id,
      po.establishment_id,
      po.dining_table_id,
      po.status,
      po.guest_count,
      po.created_at,
      po.updated_at,
      po.discount_amount,
      po.service_charge_percent,
      po.tips_amount,
      po.payment_method,
      po.paid_at,
      to_jsonb(dt.*) AS dt_json
    FROM public.pos_orders po
    LEFT JOIN public.pos_dining_tables dt ON dt.id = po.dining_table_id
    WHERE po.establishment_id = v_t.establishment_id
      AND po.status IN ('draft', 'sent')
    ORDER BY po.created_at DESC
  LOOP
    SELECT coalesce(
      jsonb_agg(sub.line_obj ORDER BY sub.sort_order, sub.created_at),
      '[]'::jsonb
    )
    INTO v_lines
    FROM (
      SELECT
        jsonb_build_object(
          'id', pol.id,
          'order_id', pol.order_id,
          'tech_card_id', pol.tech_card_id,
          'quantity', pol.quantity,
          'comment', pol.comment,
          'course_number', pol.course_number,
          'guest_number', pol.guest_number,
          'sort_order', pol.sort_order,
          'created_at', pol.created_at,
          'updated_at', pol.updated_at,
          'served_at', pol.served_at,
          'tech_cards', jsonb_build_object(
            'dish_name', tc.dish_name,
            'dish_name_localized', tc.dish_name_localized,
            'selling_price', tc.selling_price,
            'department', tc.department,
            'category', tc.category,
            'sections', tc.sections
          )
        ) AS line_obj,
        pol.sort_order,
        pol.created_at
      FROM public.pos_order_lines pol
      INNER JOIN public.tech_cards tc ON tc.id = pol.tech_card_id
      WHERE pol.order_id = o.id
        AND CASE v_t.department
          WHEN 'bar' THEN public._pos_kds_line_is_bar(tc.category, tc.sections)
          ELSE NOT public._pos_kds_line_is_bar(tc.category, tc.sections)
        END
    ) sub;

    CONTINUE WHEN coalesce(jsonb_array_length(v_lines), 0) = 0;

    SELECT
      coalesce(sum(
        (elem->>'quantity')::numeric
        * nullif(trim(elem #>> '{tech_cards,selling_price}'), '')::numeric
      ), 0),
      bool_or(
        nullif(trim(elem #>> '{tech_cards,selling_price}'), '') IS NULL
        OR trim(elem #>> '{tech_cards,selling_price}') = ''
      ),
      bool_and(
        elem->>'served_at' IS NOT NULL
        AND trim(elem->>'served_at') <> ''
      )
    INTO v_menu_subtotal, v_partial, v_all_served
    FROM jsonb_array_elements(v_lines) elem;

    v_partial := coalesce(v_partial, false);
    v_all_served := coalesce(v_all_served, false);
    v_bucket := CASE WHEN v_all_served THEN 'served' ELSE 'active' END;

    IF o.discount_amount IS NOT NULL AND o.service_charge_percent IS NOT NULL THEN
      v_grand := greatest(0::numeric, coalesce(v_menu_subtotal, 0) - greatest(0::numeric, o.discount_amount))
        + greatest(0::numeric, greatest(0::numeric, coalesce(v_menu_subtotal, 0) - greatest(0::numeric, o.discount_amount))
          * least(100::numeric, greatest(0::numeric, o.service_charge_percent)) / 100.0)
        + greatest(0::numeric, coalesce(o.tips_amount, 0));
    ELSE
      v_grand := coalesce(v_menu_subtotal, 0);
      v_partial := true;
    END IF;

    v_order := jsonb_build_object(
      'id', o.id,
      'establishment_id', o.establishment_id,
      'dining_table_id', o.dining_table_id,
      'status', o.status,
      'guest_count', o.guest_count,
      'created_at', o.created_at,
      'updated_at', o.updated_at,
      'discount_amount', coalesce(o.discount_amount, 0),
      'service_charge_percent', coalesce(o.service_charge_percent, 0),
      'tips_amount', coalesce(o.tips_amount, 0),
      'payment_method', o.payment_method,
      'paid_at', o.paid_at,
      'pos_dining_tables', coalesce(o.dt_json, '{}'::jsonb)
    );

    v_orders_accum := v_orders_accum || jsonb_build_array(
      jsonb_build_object(
        'order', v_order,
        'lines', v_lines,
        'bucket', v_bucket,
        'grand_due', v_grand,
        'menu_due_partial', v_partial,
        'menu_subtotal_raw', coalesce(v_menu_subtotal, 0)
      )
    );
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'shift_required', coalesce(v_t.require_active_shift, true),
    'shift_open', coalesce(v_shift_open, false),
    'department', v_t.department,
    'establishment_id', v_t.establishment_id,
    'orders', coalesce(v_orders_accum, '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.pos_kds_mark_line_served(
  p_token text,
  p_department text,
  p_order_id uuid,
  p_line_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_t public.pos_kitchen_display_tokens%ROWTYPE;
  v_shift_open boolean;
  v_ord record;
  v_line_cat text;
  v_line_sec jsonb;
BEGIN
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  SELECT * INTO v_t
  FROM public.pos_kitchen_display_tokens
  WHERE token = trim(p_token)
    AND revoked_at IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  IF lower(trim(p_department)) IS DISTINCT FROM v_t.department THEN
    RETURN jsonb_build_object('ok', false, 'error', 'department_mismatch');
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.pos_cash_shifts s
    WHERE s.establishment_id = v_t.establishment_id
      AND s.ended_at IS NULL
  )
  INTO v_shift_open;

  IF v_t.require_active_shift AND NOT coalesce(v_shift_open, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'shift_closed');
  END IF;

  SELECT * INTO v_ord
  FROM public.pos_orders
  WHERE id = p_order_id
    AND establishment_id = v_t.establishment_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'order_not_found');
  END IF;

  IF v_ord.status IS DISTINCT FROM 'sent' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'order_not_sent');
  END IF;

  SELECT tc.category, tc.sections
  INTO v_line_cat, v_line_sec
  FROM public.pos_order_lines pol
  INNER JOIN public.tech_cards tc ON tc.id = pol.tech_card_id
  WHERE pol.id = p_line_id
    AND pol.order_id = p_order_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'line_not_found');
  END IF;

  IF CASE v_t.department
    WHEN 'bar' THEN public._pos_kds_line_is_bar(v_line_cat, v_line_sec)
    ELSE NOT public._pos_kds_line_is_bar(v_line_cat, v_line_sec)
  END
  IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'error', 'line_wrong_department');
  END IF;

  UPDATE public.pos_order_lines
  SET served_at = now(),
      updated_at = now()
  WHERE id = p_line_id
    AND order_id = p_order_id;

  UPDATE public.pos_orders
  SET updated_at = now()
  WHERE id = p_order_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.pos_kds_tech_card_preview(
  p_token text,
  p_department text,
  p_tech_card_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_t public.pos_kitchen_display_tokens%ROWTYPE;
  v_cat text;
  v_sec jsonb;
  v_payload jsonb;
BEGIN
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  SELECT * INTO v_t
  FROM public.pos_kitchen_display_tokens
  WHERE token = trim(p_token)
    AND revoked_at IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_token');
  END IF;

  IF lower(trim(p_department)) IS DISTINCT FROM v_t.department THEN
    RETURN jsonb_build_object('ok', false, 'error', 'department_mismatch');
  END IF;

  SELECT
    tc.category,
    tc.sections,
    jsonb_build_object(
      'id', tc.id,
      'dish_name', tc.dish_name,
      'dish_name_localized', tc.dish_name_localized,
      'category', tc.category,
      'sections', tc.sections,
      'department', tc.department,
      'portion_weight', tc.portion_weight,
      'yield', tc.yield,
      'technology_localized', tc.technology_localized,
      'description_for_hall', tc.description_for_hall,
      'composition_for_hall', tc.composition_for_hall,
      'ingredients', tc.ingredients,
      'selling_price', tc.selling_price
    )
  INTO v_cat, v_sec, v_payload
  FROM public.tech_cards tc
  WHERE tc.id = p_tech_card_id
    AND tc.establishment_id = v_t.establishment_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'tech_card_not_found');
  END IF;

  IF CASE v_t.department
    WHEN 'bar' THEN public._pos_kds_line_is_bar(v_cat, v_sec)
    ELSE NOT public._pos_kds_line_is_bar(v_cat, v_sec)
  END
  IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'error', 'tech_card_wrong_department');
  END IF;

  RETURN jsonb_build_object('ok', true, 'tech_card', v_payload);
END;
$$;

REVOKE ALL ON FUNCTION public._pos_kds_line_is_bar(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._pos_kds_line_is_bar(text, jsonb) TO postgres;

REVOKE ALL ON FUNCTION public.pos_kds_fetch_orders(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pos_kds_fetch_orders(text, text) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.pos_kds_mark_line_served(text, text, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pos_kds_mark_line_served(text, text, uuid, uuid) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.pos_kds_tech_card_preview(text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pos_kds_tech_card_preview(text, text, uuid) TO anon, authenticated;
