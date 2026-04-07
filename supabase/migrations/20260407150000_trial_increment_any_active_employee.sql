-- trial_increment_usage: разрешить любому активному сотруднику заведения фиксировать счётчики триала
-- (раньше только owner / роль owner — импорт ТТК и выгрузка инвентаризации недоступны шефу и др.)

CREATE OR REPLACE FUNCTION public.trial_increment_usage(
  p_establishment_id uuid,
  p_kind text,
  p_delta integer DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trial_end timestamptz;
  v_paid boolean;
  v_inv int;
  v_ttk int;
  v_cap int;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'trial_increment_usage: must be authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.establishments e
    WHERE e.id = p_establishment_id
      AND (
        e.owner_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.employees emp
          WHERE emp.id = auth.uid()
            AND emp.establishment_id = e.id
            AND emp.is_active = true
        )
      )
  ) THEN
    RAISE EXCEPTION 'trial_increment_usage: forbidden';
  END IF;

  SELECT pro_trial_ends_at INTO v_trial_end
  FROM public.establishments
  WHERE id = p_establishment_id;

  v_paid := public.establishment_has_active_paid_pro(p_establishment_id);

  IF v_paid OR v_trial_end IS NULL OR v_trial_end <= now() THEN
    RETURN jsonb_build_object('ok', true, 'skipped', true);
  END IF;

  INSERT INTO public.establishment_trial_usage (establishment_id, inventory_exports_with_download, ttk_import_cards)
  VALUES (p_establishment_id, 0, 0)
  ON CONFLICT (establishment_id) DO NOTHING;

  SELECT COALESCE(t.inventory_exports_with_download, 0), COALESCE(t.ttk_import_cards, 0)
  INTO v_inv, v_ttk
  FROM public.establishment_trial_usage t
  WHERE t.establishment_id = p_establishment_id;

  IF lower(trim(p_kind)) = 'inventory_export' THEN
    v_cap := 3;
    IF v_inv + p_delta > v_cap THEN
      RAISE EXCEPTION 'TRIAL_INVENTORY_EXPORT_CAP';
    END IF;
    UPDATE public.establishment_trial_usage
    SET
      inventory_exports_with_download = v_inv + p_delta,
      updated_at = now()
    WHERE establishment_id = p_establishment_id
    RETURNING inventory_exports_with_download, ttk_import_cards INTO v_inv, v_ttk;
  ELSIF lower(trim(p_kind)) = 'ttk_import_cards' THEN
    v_cap := 10;
    IF v_ttk + p_delta > v_cap THEN
      RAISE EXCEPTION 'TRIAL_TTK_IMPORT_CAP';
    END IF;
    UPDATE public.establishment_trial_usage
    SET
      ttk_import_cards = v_ttk + p_delta,
      updated_at = now()
    WHERE establishment_id = p_establishment_id
    RETURNING inventory_exports_with_download, ttk_import_cards INTO v_inv, v_ttk;
  ELSE
    RAISE EXCEPTION 'trial_increment_usage: unknown kind';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'inventory_exports_with_download', v_inv,
    'ttk_import_cards', v_ttk
  );
END;
$$;

COMMENT ON FUNCTION public.trial_increment_usage(uuid, text, integer) IS
  'Увеличить счётчик использования в триале; бросает TRIAL_*_CAP при превышении. Доступ: владелец или любой активный сотрудник заведения.';
