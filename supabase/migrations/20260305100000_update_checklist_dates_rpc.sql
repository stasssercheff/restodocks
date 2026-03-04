-- Обновление deadline_at и scheduled_for_at через RPC (обходит schema cache PostgREST).
CREATE OR REPLACE FUNCTION public.update_checklist_dates(
  p_checklist_id uuid,
  p_deadline_at timestamptz DEFAULT NULL,
  p_scheduled_for_at timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE checklists
  SET
    updated_at = now(),
    deadline_at = p_deadline_at,
    scheduled_for_at = p_scheduled_for_at
  WHERE id = p_checklist_id;
$$;

GRANT EXECUTE ON FUNCTION public.update_checklist_dates(uuid, timestamptz, timestamptz) TO anon;
GRANT EXECUTE ON FUNCTION public.update_checklist_dates(uuid, timestamptz, timestamptz) TO authenticated;
