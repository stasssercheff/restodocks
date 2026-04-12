-- Фото к отдельному пункту чеклиста (шаблон): публичный URL в Storage.
ALTER TABLE public.checklist_items
  ADD COLUMN IF NOT EXISTS image_url TEXT;

COMMENT ON COLUMN public.checklist_items.image_url IS 'URL фото к пункту (не общее для чеклиста).';

-- save_checklist: сохранять image_url из JSON пунктов
DROP FUNCTION IF EXISTS public.save_checklist(uuid, text, timestamptz, jsonb, text, text, jsonb, uuid, jsonb, timestamptz, timestamptz, text, text, jsonb, jsonb);

CREATE OR REPLACE FUNCTION public.save_checklist(
  p_checklist_id uuid,
  p_name text,
  p_updated_at timestamptz,
  p_action_config jsonb,
  p_assigned_department text DEFAULT 'kitchen',
  p_assigned_section text DEFAULT NULL,
  p_assigned_section_ids jsonb DEFAULT '[]'::jsonb,
  p_assigned_employee_id uuid DEFAULT NULL,
  p_assigned_employee_ids jsonb DEFAULT '[]'::jsonb,
  p_deadline_at timestamptz DEFAULT NULL,
  p_scheduled_for_at timestamptz DEFAULT NULL,
  p_additional_name text DEFAULT NULL,
  p_type text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb,
  p_reminder_config jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item jsonb;
  v_idx int := 0;
  v_updated int;
  v_establishment_id uuid;
  v_ids jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'save_checklist: must be authenticated';
  END IF;

  SELECT establishment_id
    INTO v_establishment_id
  FROM checklists
  WHERE id = p_checklist_id;

  IF v_establishment_id IS NULL THEN
    RAISE EXCEPTION 'save_checklist: checklist % not found', p_checklist_id;
  END IF;

  IF NOT (v_establishment_id IN (SELECT current_user_establishment_ids())) THEN
    RAISE EXCEPTION 'save_checklist: access denied';
  END IF;

  v_ids := COALESCE(p_assigned_section_ids, '[]'::jsonb);
  IF jsonb_typeof(v_ids) IS DISTINCT FROM 'array' THEN
    v_ids := '[]'::jsonb;
  END IF;
  IF jsonb_array_length(v_ids) = 0 AND NULLIF(trim(COALESCE(p_assigned_section, '')), '') IS NOT NULL THEN
    v_ids := to_jsonb(ARRAY[trim(p_assigned_section)]);
  END IF;

  UPDATE checklists SET
    name = p_name,
    updated_at = p_updated_at,
    action_config = p_action_config,
    assigned_department = COALESCE(NULLIF(trim(p_assigned_department), ''), 'kitchen'),
    assigned_section = CASE WHEN jsonb_array_length(v_ids) > 0 THEN v_ids->>0 ELSE NULL END,
    assigned_section_ids = v_ids,
    assigned_employee_id = p_assigned_employee_id,
    assigned_employee_ids = p_assigned_employee_ids,
    deadline_at = p_deadline_at,
    scheduled_for_at = p_scheduled_for_at,
    additional_name = p_additional_name,
    type = p_type,
    reminder_config = p_reminder_config
  WHERE id = p_checklist_id;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RAISE EXCEPTION 'save_checklist: checklist % not found', p_checklist_id;
  END IF;

  DELETE FROM checklist_items WHERE checklist_id = p_checklist_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO checklist_items (checklist_id, title, sort_order, tech_card_id, target_quantity, target_unit, image_url)
    VALUES (
      p_checklist_id,
      COALESCE(v_item->>'title', ''),
      COALESCE((v_item->>'sort_order')::int, v_idx),
      (NULLIF(trim(v_item->>'tech_card_id'), ''))::uuid,
      (NULLIF(trim(v_item->>'target_quantity'), ''))::numeric,
      NULLIF(trim(v_item->>'target_unit'), ''),
      NULLIF(trim(v_item->>'image_url'), '')
    );
    v_idx := v_idx + 1;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.save_checklist(uuid, text, timestamptz, jsonb, text, text, jsonb, uuid, jsonb, timestamptz, timestamptz, text, text, jsonb, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_checklist(uuid, text, timestamptz, jsonb, text, text, jsonb, uuid, jsonb, timestamptz, timestamptz, text, text, jsonb, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_checklist(uuid, text, timestamptz, jsonb, text, text, jsonb, uuid, jsonb, timestamptz, timestamptz, text, text, jsonb, jsonb) TO authenticated;
