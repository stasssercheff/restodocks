-- Настройки отображения учётной записи в профиле сотрудника: тема, режим роли и т.д. (одинаково на всех устройствах).
-- Черновики форм (JSON) по user_id для продолжения с другого устройства.

ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS ui_theme text
    CHECK (ui_theme IS NULL OR ui_theme IN ('light', 'dark')),
  ADD COLUMN IF NOT EXISTS ui_view_as_owner boolean;

COMMENT ON COLUMN public.employees.ui_theme IS 'Светлая/тёмная тема; сохраняется в учётной записи и совпадает на всех устройствах';
COMMENT ON COLUMN public.employees.ui_view_as_owner IS 'Режим отображения роли (собственник / должность); общая настройка учётной записи на всех устройствах';

CREATE TABLE IF NOT EXISTS public.account_form_drafts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  draft_key text NOT NULL,
  payload jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT account_form_drafts_user_key UNIQUE (user_id, draft_key)
);

CREATE INDEX IF NOT EXISTS account_form_drafts_user_updated_idx
  ON public.account_form_drafts (user_id, updated_at DESC);

ALTER TABLE public.account_form_drafts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS account_form_drafts_select_own ON public.account_form_drafts;
CREATE POLICY account_form_drafts_select_own ON public.account_form_drafts
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS account_form_drafts_insert_own ON public.account_form_drafts;
CREATE POLICY account_form_drafts_insert_own ON public.account_form_drafts
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS account_form_drafts_update_own ON public.account_form_drafts;
CREATE POLICY account_form_drafts_update_own ON public.account_form_drafts
  FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS account_form_drafts_delete_own ON public.account_form_drafts;
CREATE POLICY account_form_drafts_delete_own ON public.account_form_drafts
  FOR DELETE USING (auth.uid() = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.account_form_drafts TO authenticated;

-- patch_my_employee_profile: ui_theme, ui_view_as_owner
CREATE OR REPLACE FUNCTION public.patch_my_employee_profile(p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT e.id INTO v_id
  FROM public.employees e
  WHERE e.id = v_uid OR e.auth_user_id = v_uid
  ORDER BY (e.id = v_uid) DESC
  LIMIT 1;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'employee row not found for current user';
  END IF;

  UPDATE public.employees e SET
    full_name = CASE WHEN p_patch ? 'full_name' THEN (p_patch->>'full_name')::text ELSE e.full_name END,
    surname = CASE WHEN p_patch ? 'surname' THEN NULLIF(p_patch->>'surname', '')::text ELSE e.surname END,
    email = CASE WHEN p_patch ? 'email' THEN (p_patch->>'email')::text ELSE e.email END,
    department = CASE WHEN p_patch ? 'department' THEN (p_patch->>'department')::text ELSE e.department END,
    section = CASE WHEN p_patch ? 'section' THEN NULLIF(p_patch->>'section', '')::text ELSE e.section END,
    roles = CASE WHEN p_patch ? 'roles' AND jsonb_typeof(p_patch->'roles') = 'array'
      THEN ARRAY(SELECT jsonb_array_elements_text(p_patch->'roles'))::text[]
      ELSE e.roles END,
    personal_pin = CASE WHEN p_patch ? 'personal_pin' THEN NULLIF(p_patch->>'personal_pin', '')::text ELSE e.personal_pin END,
    avatar_url = CASE WHEN p_patch ? 'avatar_url' THEN NULLIF(p_patch->>'avatar_url', '')::text ELSE e.avatar_url END,
    subscription_plan = CASE WHEN p_patch ? 'subscription_plan' THEN NULLIF(p_patch->>'subscription_plan', '')::text ELSE e.subscription_plan END,
    preferred_language = CASE WHEN p_patch ? 'preferred_language' THEN (p_patch->>'preferred_language')::text ELSE e.preferred_language END,
    preferred_currency = CASE WHEN p_patch ? 'preferred_currency' THEN NULLIF(p_patch->>'preferred_currency', '')::text ELSE e.preferred_currency END,
    ui_theme = CASE WHEN p_patch ? 'ui_theme' THEN NULLIF(p_patch->>'ui_theme', '')::text ELSE e.ui_theme END,
    ui_view_as_owner = CASE WHEN p_patch ? 'ui_view_as_owner' THEN (p_patch->>'ui_view_as_owner')::boolean ELSE e.ui_view_as_owner END,
    getting_started_shown = CASE WHEN p_patch ? 'getting_started_shown' THEN (p_patch->>'getting_started_shown')::boolean ELSE e.getting_started_shown END,
    first_session_at = CASE
      WHEN p_patch ? 'first_session_at' AND NULLIF(p_patch->>'first_session_at', '') IS NOT NULL
      THEN (p_patch->>'first_session_at')::timestamptz
      ELSE e.first_session_at END,
    payment_type = CASE WHEN p_patch ? 'payment_type' THEN NULLIF(p_patch->>'payment_type', '')::text ELSE e.payment_type END,
    rate_per_shift = CASE
      WHEN p_patch ? 'rate_per_shift' AND jsonb_typeof(p_patch->'rate_per_shift') = 'null' THEN NULL
      WHEN p_patch ? 'rate_per_shift' THEN (p_patch->>'rate_per_shift')::double precision
      ELSE e.rate_per_shift END,
    hourly_rate = CASE
      WHEN p_patch ? 'hourly_rate' AND jsonb_typeof(p_patch->'hourly_rate') = 'null' THEN NULL
      WHEN p_patch ? 'hourly_rate' THEN (p_patch->>'hourly_rate')::double precision
      ELSE e.hourly_rate END,
    is_active = CASE WHEN p_patch ? 'is_active' THEN (p_patch->>'is_active')::boolean ELSE e.is_active END,
    data_access_enabled = CASE WHEN p_patch ? 'data_access_enabled' THEN (p_patch->>'data_access_enabled')::boolean ELSE e.data_access_enabled END,
    can_edit_own_schedule = CASE WHEN p_patch ? 'can_edit_own_schedule' THEN (p_patch->>'can_edit_own_schedule')::boolean ELSE e.can_edit_own_schedule END,
    owner_access_level = CASE WHEN p_patch ? 'owner_access_level' THEN (p_patch->>'owner_access_level')::text ELSE e.owner_access_level END,
    employment_status = CASE WHEN p_patch ? 'employment_status' THEN (p_patch->>'employment_status')::text ELSE e.employment_status END,
    employment_start_date = CASE
      WHEN p_patch ? 'employment_start_date' AND NULLIF(p_patch->>'employment_start_date', '') IS NOT NULL
      THEN (p_patch->>'employment_start_date')::date
      ELSE e.employment_start_date END,
    employment_end_date = CASE
      WHEN p_patch ? 'employment_end_date' AND NULLIF(p_patch->>'employment_end_date', '') IS NOT NULL
      THEN (p_patch->>'employment_end_date')::date
      ELSE e.employment_end_date END,
    birthday = CASE
      WHEN p_patch ? 'birthday' AND NULLIF(p_patch->>'birthday', '') IS NOT NULL
      THEN (p_patch->>'birthday')::date
      ELSE e.birthday END,
    updated_at = now()
  WHERE e.id = v_id;

  RETURN (SELECT to_jsonb(r.*) FROM public.employees r WHERE r.id = v_id);
END;
$$;

REVOKE ALL ON FUNCTION public.patch_my_employee_profile(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.patch_my_employee_profile(jsonb) TO authenticated;
