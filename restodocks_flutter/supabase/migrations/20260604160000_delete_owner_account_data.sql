-- Удаление всех заведений владельца и связанных данных по PIN каждого «корня» (основное заведение без родителя-владельца).
-- Дальше клиент вызывает Edge purge-owner-auth для удаления auth.users.

CREATE OR REPLACE FUNCTION public.delete_owner_account_data(
  p_pins jsonb,
  p_email text
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  r RECORD;
  v_given text;
  v_expected text;
  v_need_pins boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF EXISTS (SELECT 1 FROM employees WHERE id = v_uid)
     AND NOT EXISTS (SELECT 1 FROM establishments WHERE owner_id = v_uid) THEN
    RAISE EXCEPTION 'Only primary owner can delete account';
  END IF;

  SELECT email INTO v_email
  FROM employees
  WHERE id = v_uid;

  IF v_email IS NULL THEN
    SELECT por.email INTO v_email
    FROM pending_owner_registrations por
    WHERE por.auth_user_id = v_uid
    ORDER BY por.updated_at DESC NULLS LAST
    LIMIT 1;
  END IF;

  IF v_email IS NULL OR lower(trim(v_email)) IS DISTINCT FROM lower(trim(coalesce(p_email, ''))) THEN
    RAISE EXCEPTION 'Email does not match';
  END IF;

  v_need_pins := EXISTS (
    SELECT 1
    FROM establishments e
    WHERE e.owner_id = v_uid
      AND (
        e.parent_establishment_id IS NULL
        OR NOT EXISTS (
          SELECT 1
          FROM establishments p
          WHERE p.id = e.parent_establishment_id
            AND p.owner_id = v_uid
        )
      )
  );

  IF v_need_pins THEN
    FOR r IN
      SELECT e.id, e.pin_code, e.name
      FROM establishments e
      WHERE e.owner_id = v_uid
        AND (
          e.parent_establishment_id IS NULL
          OR NOT EXISTS (
            SELECT 1
            FROM establishments p
            WHERE p.id = e.parent_establishment_id
              AND p.owner_id = v_uid
          )
        )
    LOOP
      v_expected := upper(trim(coalesce(r.pin_code, '')));
      v_given := upper(trim(coalesce(p_pins ->> r.id::text, '')));
      IF v_given = '' OR v_given IS DISTINCT FROM v_expected THEN
        RAISE EXCEPTION 'Invalid PIN for establishment';
      END IF;
    END LOOP;
  END IF;

  DELETE FROM public.establishment_data_clone_requests
  WHERE owner_id = v_uid;

  FOR r IN
    SELECT e.id
    FROM establishments e
    WHERE e.owner_id = v_uid
      AND (
        e.parent_establishment_id IS NULL
        OR NOT EXISTS (
          SELECT 1
          FROM establishments p
          WHERE p.id = e.parent_establishment_id
            AND p.owner_id = v_uid
        )
      )
  LOOP
    PERFORM public._delete_establishment_cascade(r.id);
  END LOOP;

  DELETE FROM public.pending_owner_registrations
  WHERE auth_user_id = v_uid;
END;
$$;

COMMENT ON FUNCTION public.delete_owner_account_data(jsonb, text) IS
  'Владелец: проверка email и PIN по каждому корневому заведению, каскадное удаление всех своих заведений, очистка заявок клонирования и pending_owner. Удаление auth — отдельно (Edge).';

REVOKE ALL ON FUNCTION public.delete_owner_account_data(jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_owner_account_data(jsonb, text) TO authenticated;
