-- Права доступа к разделу "Экран заказов" и открытию смены для сотрудников кухни.
-- Назначают только owner и executive_chef.

CREATE TABLE IF NOT EXISTS public.pos_kds_shift_access_permissions (
  establishment_id uuid NOT NULL REFERENCES public.establishments(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  created_by_employee_id uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (establishment_id, employee_id)
);

ALTER TABLE public.pos_kds_shift_access_permissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pos_kds_shift_access_permissions_select ON public.pos_kds_shift_access_permissions;
CREATE POLICY pos_kds_shift_access_permissions_select
  ON public.pos_kds_shift_access_permissions
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (SELECT public.current_user_establishment_ids())
  );

DROP POLICY IF EXISTS pos_kds_shift_access_permissions_insert ON public.pos_kds_shift_access_permissions;
CREATE POLICY pos_kds_shift_access_permissions_insert
  ON public.pos_kds_shift_access_permissions
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (SELECT public.current_user_establishment_ids())
    AND EXISTS (
      SELECT 1
      FROM public.employees me
      WHERE me.auth_user_id = auth.uid()
        AND me.establishment_id = pos_kds_shift_access_permissions.establishment_id
        AND me.is_active = true
        AND ('owner' = ANY(me.roles) OR 'executive_chef' = ANY(me.roles))
    )
  );

DROP POLICY IF EXISTS pos_kds_shift_access_permissions_delete ON public.pos_kds_shift_access_permissions;
CREATE POLICY pos_kds_shift_access_permissions_delete
  ON public.pos_kds_shift_access_permissions
  FOR DELETE TO authenticated
  USING (
    establishment_id IN (SELECT public.current_user_establishment_ids())
    AND EXISTS (
      SELECT 1
      FROM public.employees me
      WHERE me.auth_user_id = auth.uid()
        AND me.establishment_id = pos_kds_shift_access_permissions.establishment_id
        AND me.is_active = true
        AND ('owner' = ANY(me.roles) OR 'executive_chef' = ANY(me.roles))
    )
  );
