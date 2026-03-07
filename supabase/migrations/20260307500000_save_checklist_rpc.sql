-- RPC для сохранения чеклиста (обходит возможные проблемы с RLS).
-- Проверяет доступ пользователя внутри функции, затем выполняет UPDATE/DELETE/INSERT.

CREATE OR REPLACE FUNCTION public.save_checklist(
  p_checklist_id uuid,
  p_name text,
  p_updated_at timestamptz,
  p_action_config jsonb,
  p_assigned_department text DEFAULT 'kitchen',
  p_assigned_section text DEFAULT NULL,
  p_assigned_employee_id uuid DEFAULT NULL,
  p_assigned_employee_ids jsonb DEFAULT '[]'::jsonb,
  p_deadline_at timestamptz DEFAULT NULL,
  p_scheduled_for_at timestamptz DEFAULT NULL,
  p_additional_name text DEFAULT NULL,
  p_type text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_establishment_id uuid;
  v_item jsonb;
  v_idx int := 0;
BEGIN
  -- 1. Проверить что чеклист существует и пользователь имеет доступ
  -- (прямая проверка owner/employee, без current_user_establishment_ids)
  SELECT c.establishment_id INTO v_establishment_id
  FROM checklists c
  WHERE c.id = p_checklist_id
    AND (
      EXISTS (SELECT 1 FROM establishments e WHERE e.id = c.establishment_id AND e.owner_id = auth.uid())
      OR EXISTS (SELECT 1 FROM employees emp WHERE emp.establishment_id = c.establishment_id AND emp.id = auth.uid())
    );

  IF v_establishment_id IS NULL THEN
    RAISE EXCEPTION 'checklist not found or access denied (auth.uid=% establishment?)', COALESCE(auth.uid()::text, 'NULL');
  END IF;

  IF is_current_user_view_only_owner() THEN
    RAISE EXCEPTION 'view-only owner cannot edit checklists';
  END IF;

  -- 2. Обновить заголовок чеклиста
  UPDATE checklists SET
    name = p_name,
    updated_at = p_updated_at,
    action_config = p_action_config,
    assigned_department = COALESCE(NULLIF(trim(p_assigned_department), ''), 'kitchen'),
    assigned_section = p_assigned_section,
    assigned_employee_id = p_assigned_employee_id,
    assigned_employee_ids = p_assigned_employee_ids,
    deadline_at = p_deadline_at,
    scheduled_for_at = p_scheduled_for_at,
    additional_name = p_additional_name,
    type = p_type
  WHERE id = p_checklist_id;

  -- 3. Удалить старые пункты
  DELETE FROM checklist_items WHERE checklist_id = p_checklist_id;

  -- 4. Вставить новые пункты
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO checklist_items (checklist_id, title, sort_order, tech_card_id, target_quantity, target_unit)
    VALUES (
      p_checklist_id,
      COALESCE(v_item->>'title', ''),
      COALESCE((v_item->>'sort_order')::int, v_idx),
      (NULLIF(trim(v_item->>'tech_card_id'), ''))::uuid,
      (NULLIF(trim(v_item->>'target_quantity'), ''))::numeric,
      NULLIF(trim(v_item->>'target_unit'), '')
    );
    v_idx := v_idx + 1;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.save_checklist IS 'Сохраняет чеклист и его пункты. SECURITY DEFINER для обхода RLS при проверенном доступе.';

GRANT EXECUTE ON FUNCTION public.save_checklist TO authenticated;
