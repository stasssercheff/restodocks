-- После удаления заведения: auth.users для «осиротевших» участников (employees.id / auth_user_id),
-- чтобы тот же email мог зарегистрироваться снова.
-- Админка: admin_delete_establishment возвращает purge_auth_user_ids → deleteUser (service_role) в Next.js.
-- Владелец: delete_establishment_by_owner кладёт строки в establishment_auth_purge_queue + purge_auth_token;
-- Edge purge-establishment-auth-queue (JWT = initiator) вызывает auth.admin.deleteUser.

CREATE TABLE IF NOT EXISTS public.establishment_auth_purge_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  disposable_token uuid NOT NULL,
  initiator_user_id uuid NOT NULL,
  auth_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (disposable_token, auth_user_id)
);

CREATE INDEX IF NOT EXISTS establishment_auth_purge_queue_token_idx
  ON public.establishment_auth_purge_queue (disposable_token);

COMMENT ON TABLE public.establishment_auth_purge_queue IS
  'Очередь удаления auth.users после delete_establishment_by_owner; обрабатывает Edge purge-establishment-auth-queue.';

ALTER TABLE public.establishment_auth_purge_queue ENABLE ROW LEVEL SECURITY;

-- Подключённые клиенты не читают очередь; Edge — service_role.

CREATE OR REPLACE FUNCTION public._establishment_subtree_ids(p_root uuid)
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH RECURSIVE tree AS (
    SELECT e.id
    FROM public.establishments e
    WHERE e.id = p_root
    UNION ALL
    SELECT c.id
    FROM public.establishments c
    INNER JOIN tree t ON c.parent_establishment_id = t.id
  )
  SELECT COALESCE(array_agg(id), ARRAY[]::uuid[]) FROM tree;
$$;

CREATE OR REPLACE FUNCTION public._orphaned_auth_user_ids(p_candidates uuid[])
RETURNS uuid[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid;
  v_out uuid[] := ARRAY[]::uuid[];
BEGIN
  IF p_candidates IS NULL OR cardinality(p_candidates) = 0 THEN
    RETURN ARRAY[]::uuid[];
  END IF;

  FOR v_uid IN
    SELECT DISTINCT u
    FROM unnest(p_candidates) AS u
    WHERE u IS NOT NULL
  LOOP
    IF EXISTS (
      SELECT 1
      FROM public.employees e
      WHERE e.id = v_uid OR e.auth_user_id = v_uid
    ) THEN
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.establishments s WHERE s.owner_id = v_uid
    ) THEN
      CONTINUE;
    END IF;

    v_out := array_append(v_out, v_uid);
  END LOOP;

  RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public._establishment_subtree_ids(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._orphaned_auth_user_ids(uuid[]) FROM PUBLIC;

DROP FUNCTION IF EXISTS public.admin_delete_establishment(uuid);

CREATE OR REPLACE FUNCTION public.admin_delete_establishment(p_establishment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_subtree uuid[] := public._establishment_subtree_ids(p_establishment_id);
  v_auth_ids uuid[];
  v_purge_ids uuid[];
BEGIN
  SELECT COALESCE(array_agg(DISTINCT x.auth_id), ARRAY[]::uuid[])
  INTO v_auth_ids
  FROM (
    SELECT e.id AS auth_id
    FROM public.employees e
    WHERE e.establishment_id = ANY (v_subtree)
    UNION
    SELECT e.auth_user_id AS auth_id
    FROM public.employees e
    WHERE e.establishment_id = ANY (v_subtree)
      AND e.auth_user_id IS NOT NULL
  ) x
  WHERE x.auth_id IS NOT NULL;

  PERFORM public._delete_establishment_cascade(p_establishment_id);

  v_purge_ids := public._orphaned_auth_user_ids(v_auth_ids);

  RETURN jsonb_build_object(
    'ok', true,
    'purge_auth_user_ids', to_jsonb(v_purge_ids)
  );
END;
$$;

COMMENT ON FUNCTION public.admin_delete_establishment(uuid) IS
  'Удаление заведения (админка, service_role). Возвращает ok и purge_auth_user_ids для удаления из Auth.';

REVOKE ALL ON FUNCTION public.admin_delete_establishment(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_establishment(uuid) TO service_role;

DROP FUNCTION IF EXISTS public.delete_establishment_by_owner(uuid, text, text);

CREATE OR REPLACE FUNCTION public.delete_establishment_by_owner(
  p_establishment_id uuid,
  p_pin_code text,
  p_email text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner_id uuid;
  v_pin text;
  v_emp_email text;
  v_subtree uuid[];
  v_auth_ids uuid[];
  v_purge_ids uuid[];
  v_token uuid;
BEGIN
  SELECT owner_id, pin_code
  INTO v_owner_id, v_pin
  FROM public.establishments
  WHERE id = p_establishment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Establishment not found';
  END IF;

  IF v_owner_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Only owner can delete this establishment';
  END IF;

  IF upper(trim(COALESCE(p_pin_code, ''))) != upper(trim(COALESCE(v_pin, ''))) THEN
    RAISE EXCEPTION 'Invalid PIN code';
  END IF;

  SELECT email
  INTO v_emp_email
  FROM public.employees
  WHERE id = v_owner_id;

  IF v_emp_email IS NULL OR lower(trim(v_emp_email)) != lower(trim(COALESCE(p_email, ''))) THEN
    RAISE EXCEPTION 'Email does not match';
  END IF;

  v_subtree := public._establishment_subtree_ids(p_establishment_id);

  SELECT COALESCE(array_agg(DISTINCT x.auth_id), ARRAY[]::uuid[])
  INTO v_auth_ids
  FROM (
    SELECT e.id AS auth_id
    FROM public.employees e
    WHERE e.establishment_id = ANY (v_subtree)
    UNION
    SELECT e.auth_user_id AS auth_id
    FROM public.employees e
    WHERE e.establishment_id = ANY (v_subtree)
      AND e.auth_user_id IS NOT NULL
  ) x
  WHERE x.auth_id IS NOT NULL;

  PERFORM public._delete_establishment_cascade(p_establishment_id);

  v_purge_ids := public._orphaned_auth_user_ids(v_auth_ids);

  IF cardinality(v_purge_ids) > 0 THEN
    v_token := gen_random_uuid();
    INSERT INTO public.establishment_auth_purge_queue (disposable_token, initiator_user_id, auth_user_id)
    SELECT v_token, auth.uid(), unnest(v_purge_ids);
  ELSE
    v_token := NULL;
  END IF;

  RETURN jsonb_build_object(
    'purge_auth_token', to_jsonb(v_token)
  );
END;
$$;

COMMENT ON FUNCTION public.delete_establishment_by_owner(uuid, text, text) IS
  'Удаляет заведение владельцем (PIN + email). Возвращает purge_auth_token для Edge purge-establishment-auth-queue.';

REVOKE ALL ON FUNCTION public.delete_establishment_by_owner(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_establishment_by_owner(uuid, text, text) TO authenticated;
