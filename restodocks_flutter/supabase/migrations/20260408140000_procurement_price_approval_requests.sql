-- Согласование обновления цен номенклатуры после приёмки (не-шеф → шеф во входящих).
CREATE TABLE IF NOT EXISTS public.procurement_price_approval_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES public.establishments(id) ON DELETE CASCADE,
  receipt_document_id UUID NOT NULL REFERENCES public.procurement_receipt_documents(id) ON DELETE CASCADE,
  nomenclature_establishment_id UUID NOT NULL,
  created_by_employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'applied', 'cancelled')),
  lines JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,
  resolved_by_employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_proc_price_approval_est
  ON public.procurement_price_approval_requests(establishment_id);
CREATE INDEX IF NOT EXISTS idx_proc_price_approval_pending
  ON public.procurement_price_approval_requests(establishment_id, status)
  WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_proc_price_approval_receipt
  ON public.procurement_price_approval_requests(receipt_document_id);

COMMENT ON TABLE public.procurement_price_approval_requests IS
  'Очередь согласования цен номенклатуры после приёмки. lines: [{productId, productName, unit, oldPricePerUnit, newPricePerUnit}].';

ALTER TABLE public.procurement_price_approval_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_proc_price_approval_select" ON public.procurement_price_approval_requests;
CREATE POLICY "auth_proc_price_approval_select" ON public.procurement_price_approval_requests
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM public.employees WHERE id = auth.uid()
    )
  );

-- INSERT только через Edge (service role); клиент не создаёт заявки напрямую.

DROP POLICY IF EXISTS "auth_proc_price_approval_update" ON public.procurement_price_approval_requests;
CREATE POLICY "auth_proc_price_approval_update" ON public.procurement_price_approval_requests
  FOR UPDATE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM public.employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM public.employees WHERE id = auth.uid()
    )
  );

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.procurement_price_approval_requests;
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
