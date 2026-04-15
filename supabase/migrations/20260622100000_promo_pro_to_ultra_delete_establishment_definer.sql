-- 1) Промокоды: шаблоны с тарифом pro → ultra (повторяемо; новые строки после старых миграций).
-- 2) Дефолт для новых промокодов — ultra, не pro.
-- 3) Удаление заведения из кабинета: delete_establishment_by_owner как SECURITY DEFINER (как каскад),
--    чтобы RLS/краевые случаи не ломали SELECT при проверке PIN/email.
-- 4) Каскад: явно чистим строки по establishment_id в таблицах, добавленных после базового каскада.

-- --- Промокоды ---
UPDATE public.promo_codes
SET grants_subscription_type = 'ultra'
WHERE lower(trim(grants_subscription_type)) = 'pro';

ALTER TABLE public.promo_codes
  ALTER COLUMN grants_subscription_type SET DEFAULT 'ultra';

-- --- Удаление заведения владельцем ---
CREATE OR REPLACE FUNCTION public.delete_establishment_by_owner (
  p_establishment_id uuid,
  p_pin_code text,
  p_email text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid;
  v_pin text;
  v_emp_email text;
BEGIN
  SELECT
    owner_id,
    pin_code
  INTO
    v_owner_id,
    v_pin
  FROM
    establishments
  WHERE
    id = p_establishment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Establishment not found';
  END IF;

  IF v_owner_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Only owner can delete this establishment';
  END IF;

  IF upper(trim(COALESCE(p_pin_code, ''))) != upper(trim(COALESCE(v_pin, ''))) THEN
    RAISE EXCEPTION 'Invalid PIN code';
  END IF;

  SELECT
    email
  INTO v_emp_email
  FROM
    employees
  WHERE
    id = v_owner_id;

  IF v_emp_email IS NULL OR lower(trim(v_emp_email)) != lower(trim(COALESCE(p_email, ''))) THEN
    RAISE EXCEPTION 'Email does not match';
  END IF;

  PERFORM public._delete_establishment_cascade (p_establishment_id);
END;
$$;

COMMENT ON FUNCTION public.delete_establishment_by_owner (uuid, text, text) IS
  'Удаляет заведение владельцем (PIN + email). SECURITY DEFINER; проверки по auth.uid().';

REVOKE ALL ON FUNCTION public.delete_establishment_by_owner (uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_establishment_by_owner (uuid, text, text) TO authenticated;

-- --- Расширенный каскад (идемпотентные DELETE, если таблица есть) ---
CREATE OR REPLACE FUNCTION public._delete_establishment_cascade (p_establishment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id FROM establishments WHERE parent_establishment_id = p_establishment_id
  LOOP
    PERFORM _delete_establishment_cascade (r.id);
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

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'establishment_entitlement_addons') THEN
    DELETE FROM establishment_entitlement_addons WHERE establishment_id = p_establishment_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'establishment_trial_usage') THEN
    DELETE FROM establishment_trial_usage WHERE establishment_id = p_establishment_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'apple_iap_subscription_claims') THEN
    DELETE FROM apple_iap_subscription_claims WHERE establishment_id = p_establishment_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'iap_billing_test_state') THEN
    DELETE FROM iap_billing_test_state WHERE establishment_id = p_establishment_id;
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

REVOKE ALL ON FUNCTION public._delete_establishment_cascade (uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._delete_establishment_cascade (uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public._delete_establishment_cascade (uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
