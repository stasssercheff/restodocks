-- RPC: Удаление заведения владельцем (с проверкой PIN и email)
-- Используется из кабинета собственника. Админ удаляет через API с service_role.
CREATE OR REPLACE FUNCTION public.delete_establishment_by_owner(
  p_establishment_id uuid,
  p_pin_code text,
  p_email text
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid;
  v_pin text;
  v_emp_email text;
BEGIN
  -- Проверка: заведение существует
  SELECT owner_id, pin_code INTO v_owner_id, v_pin
  FROM establishments WHERE id = p_establishment_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Establishment not found';
  END IF;

  -- Только владелец может удалить
  IF v_owner_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Only owner can delete this establishment';
  END IF;

  -- Проверка PIN (без учёта регистра, пробелов)
  IF UPPER(TRIM(COALESCE(p_pin_code, ''))) != UPPER(TRIM(COALESCE(v_pin, ''))) THEN
    RAISE EXCEPTION 'Invalid PIN code';
  END IF;

  -- Проверка email: владелец (owner_id) должен иметь совпадающий email
  SELECT email INTO v_emp_email
  FROM employees WHERE id = v_owner_id;
  IF v_emp_email IS NULL OR LOWER(TRIM(v_emp_email)) != LOWER(TRIM(COALESCE(p_email, ''))) THEN
    RAISE EXCEPTION 'Email does not match';
  END IF;

  -- Выполняем каскадное удаление
  PERFORM _delete_establishment_cascade(p_establishment_id);
END;
$$;

COMMENT ON FUNCTION public.delete_establishment_by_owner IS 'Удаляет заведение владельцем. Проверяет PIN и email.';

-- Внутренняя функция: каскадное удаление заведения и всех связанных данных
CREATE OR REPLACE FUNCTION public._delete_establishment_cascade(p_establishment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  r RECORD;
BEGIN
  -- 1. Если это основное заведение — сначала удаляем филиалы
  FOR r IN SELECT id FROM establishments WHERE parent_establishment_id = p_establishment_id
  LOOP
    PERFORM _delete_establishment_cascade(r.id);
  END LOOP;

  -- 2. Удаляем данные заведения (порядок важен из‑за FK)
  DELETE FROM password_reset_tokens WHERE employee_id IN (SELECT id FROM employees WHERE establishment_id = p_establishment_id);
  DELETE FROM co_owner_invitations WHERE establishment_id = p_establishment_id;
  DELETE FROM employee_direct_messages WHERE sender_employee_id IN (SELECT id FROM employees WHERE establishment_id = p_establishment_id)
     OR recipient_employee_id IN (SELECT id FROM employees WHERE establishment_id = p_establishment_id);
  DELETE FROM inventory_documents WHERE establishment_id = p_establishment_id;
  DELETE FROM order_documents WHERE establishment_id = p_establishment_id;
  DELETE FROM inventory_drafts WHERE establishment_id = p_establishment_id;
  DELETE FROM establishment_schedule_data WHERE establishment_id = p_establishment_id;
  DELETE FROM establishment_order_list_data WHERE establishment_id = p_establishment_id;
  DELETE FROM product_price_history WHERE establishment_id = p_establishment_id;
  DELETE FROM establishment_products WHERE establishment_id = p_establishment_id;
  DELETE FROM tt_ingredients WHERE tech_card_id IN (SELECT id FROM tech_cards WHERE establishment_id = p_establishment_id);
  DELETE FROM tech_cards WHERE establishment_id = p_establishment_id;
  DELETE FROM checklist_items WHERE checklist_id IN (SELECT id FROM checklists WHERE establishment_id = p_establishment_id);
  DELETE FROM checklist_submissions WHERE checklist_id IN (SELECT id FROM checklists WHERE establishment_id = p_establishment_id);
  DELETE FROM checklists WHERE establishment_id = p_establishment_id;

  -- iiko_blank_storage, iiko_products — если существуют
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'iiko_blank_storage') THEN
    DELETE FROM iiko_blank_storage WHERE establishment_id = p_establishment_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'iiko_products') THEN
    DELETE FROM iiko_products WHERE establishment_id = p_establishment_id;
  END IF;

  -- 3. Обнуляем owner_id у заведения (employees ссылаются на establishments)
  UPDATE establishments SET owner_id = NULL WHERE id = p_establishment_id;

  -- 4. Удаляем сотрудников
  DELETE FROM employees WHERE establishment_id = p_establishment_id;

  -- 5. Удаляем заведение
  DELETE FROM establishments WHERE id = p_establishment_id;
END;
$$;
