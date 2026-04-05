-- Дополнение к 20260406220000:
-- 1) Сбрасывать owner_id и для удаляемой строки establishments (владелец может быть в employees другого заведения).
-- 2) Удалять журналы HACСП с establishment_id до DELETE employees — иначе ON DELETE RESTRICT на created_by_employee_id.

CREATE OR REPLACE FUNCTION public._delete_establishment_cascade(p_establishment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id FROM establishments WHERE parent_establishment_id = p_establishment_id
  LOOP
    PERFORM _delete_establishment_cascade(r.id);
  END LOOP;

  DELETE FROM pending_owner_registrations WHERE establishment_id = p_establishment_id;
  DELETE FROM password_reset_tokens WHERE employee_id IN (SELECT id FROM employees WHERE establishment_id = p_establishment_id);
  DELETE FROM co_owner_invitations WHERE establishment_id = p_establishment_id;
  DELETE FROM employee_direct_messages WHERE sender_employee_id IN (SELECT id FROM employees WHERE establishment_id = p_establishment_id)
     OR recipient_employee_id IN (SELECT id FROM employees WHERE establishment_id = p_establishment_id);

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'chat_room_messages') THEN
    DELETE FROM chat_room_messages WHERE chat_room_id IN (SELECT id FROM chat_rooms WHERE establishment_id = p_establishment_id);
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'chat_room_members') THEN
    DELETE FROM chat_room_members WHERE chat_room_id IN (SELECT id FROM chat_rooms WHERE establishment_id = p_establishment_id);
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'chat_rooms') THEN
    DELETE FROM chat_rooms WHERE establishment_id = p_establishment_id;
  END IF;

  DELETE FROM inventory_documents WHERE establishment_id = p_establishment_id;
  DELETE FROM order_documents WHERE establishment_id = p_establishment_id;
  DELETE FROM inventory_drafts WHERE establishment_id = p_establishment_id;
  DELETE FROM establishment_schedule_data WHERE establishment_id = p_establishment_id;
  DELETE FROM establishment_order_list_data WHERE establishment_id = p_establishment_id;
  DELETE FROM product_price_history WHERE establishment_id = p_establishment_id;
  DELETE FROM establishment_products WHERE establishment_id = p_establishment_id;
  DELETE FROM tt_ingredients WHERE tech_card_id IN (SELECT id FROM tech_cards WHERE establishment_id = p_establishment_id);
  DELETE FROM tech_cards WHERE establishment_id = p_establishment_id;
  DELETE FROM checklist_drafts WHERE checklist_id IN (SELECT id FROM checklists WHERE establishment_id = p_establishment_id);
  DELETE FROM checklist_items WHERE checklist_id IN (SELECT id FROM checklists WHERE establishment_id = p_establishment_id);
  DELETE FROM checklist_submissions WHERE checklist_id IN (SELECT id FROM checklists WHERE establishment_id = p_establishment_id);
  DELETE FROM checklists WHERE establishment_id = p_establishment_id;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'iiko_blank_storage') THEN
    DELETE FROM iiko_blank_storage WHERE establishment_id = p_establishment_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'iiko_products') THEN
    DELETE FROM iiko_products WHERE establishment_id = p_establishment_id;
  END IF;

  -- HACCP: RESTRICT на employees — убрать до DELETE employees
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'haccp_numeric_logs') THEN
    DELETE FROM haccp_numeric_logs WHERE establishment_id = p_establishment_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'haccp_status_logs') THEN
    DELETE FROM haccp_status_logs WHERE establishment_id = p_establishment_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'haccp_quality_logs') THEN
    DELETE FROM haccp_quality_logs WHERE establishment_id = p_establishment_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'haccp_logs') THEN
    DELETE FROM haccp_logs WHERE establishment_id = p_establishment_id;
  END IF;

  UPDATE establishments
  SET owner_id = NULL
  WHERE id = p_establishment_id
     OR owner_id IN (SELECT id FROM employees WHERE establishment_id = p_establishment_id);

  DELETE FROM employees WHERE establishment_id = p_establishment_id;
  DELETE FROM establishments WHERE id = p_establishment_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public._delete_establishment_cascade(uuid) TO service_role;
