-- Триал 72 часа:
-- 1) inventory_export: максимум 3 выгрузки
-- 2) ttk_import_cards: максимум 10 карточек
-- 3) device_save:<doc_kind>: максимум 3 сохранения на устройство для каждого вида документа

CREATE TABLE IF NOT EXISTS public.establishment_trial_usage_device_saves (
  establishment_id uuid NOT NULL REFERENCES public.establishments(id) ON DELETE CASCADE,
  doc_kind text NOT NULL,
  saves_count integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (establishment_id, doc_kind)
);

ALTER TABLE public.establishment_trial_usage_device_saves ENABLE ROW LEVEL SECURITY;

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
  v_kind text;
  v_doc_kind text;
  v_doc_used int;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'trial_increment_usage: must be authenticated';
  END IF;

  IF p_delta IS NULL OR p_delta < 1 THEN
    RAISE EXCEPTION 'trial_increment_usage: p_delta must be >= 1';
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

  INSERT INTO public.establishment_trial_usage (
    establishment_id,
    inventory_exports_with_download,
    ttk_import_cards
  )
  VALUES (p_establishment_id, 0, 0)
  ON CONFLICT (establishment_id) DO NOTHING;

  SELECT COALESCE(t.inventory_exports_with_download, 0), COALESCE(t.ttk_import_cards, 0)
  INTO v_inv, v_ttk
  FROM public.establishment_trial_usage t
  WHERE t.establishment_id = p_establishment_id;

  v_kind := lower(trim(coalesce(p_kind, '')));

  IF v_kind = 'inventory_export' THEN
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

    RETURN jsonb_build_object(
      'ok', true,
      'inventory_exports_with_download', v_inv,
      'ttk_import_cards', v_ttk
    );
  ELSIF v_kind = 'ttk_import_cards' THEN
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

    RETURN jsonb_build_object(
      'ok', true,
      'inventory_exports_with_download', v_inv,
      'ttk_import_cards', v_ttk
    );
  ELSIF v_kind LIKE 'device_save:%' THEN
    v_doc_kind := substring(v_kind from length('device_save:') + 1);
    IF v_doc_kind IS NULL OR length(trim(v_doc_kind)) = 0 THEN
      RAISE EXCEPTION 'trial_increment_usage: invalid device doc kind';
    END IF;

    INSERT INTO public.establishment_trial_usage_device_saves(
      establishment_id, doc_kind, saves_count, updated_at
    )
    VALUES (p_establishment_id, v_doc_kind, 0, now())
    ON CONFLICT (establishment_id, doc_kind) DO NOTHING;

    SELECT COALESCE(s.saves_count, 0)
    INTO v_doc_used
    FROM public.establishment_trial_usage_device_saves s
    WHERE s.establishment_id = p_establishment_id
      AND s.doc_kind = v_doc_kind;

    v_cap := 3;
    IF v_doc_used + p_delta > v_cap THEN
      RAISE EXCEPTION 'TRIAL_DEVICE_SAVE_CAP';
    END IF;

    UPDATE public.establishment_trial_usage_device_saves
    SET
      saves_count = v_doc_used + p_delta,
      updated_at = now()
    WHERE establishment_id = p_establishment_id
      AND doc_kind = v_doc_kind
    RETURNING saves_count INTO v_doc_used;

    RETURN jsonb_build_object(
      'ok', true,
      'doc_kind', v_doc_kind,
      'device_saves_count', v_doc_used
    );
  ELSE
    RAISE EXCEPTION 'trial_increment_usage: unknown kind';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.trial_increment_usage(uuid, text, integer) IS
  'Триал-счётчики: inventory_export=3, ttk_import_cards=10, device_save:<doc_kind>=3.';
