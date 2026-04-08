-- Зависимость: документы приёмки поставок (если миграция 20260407120000 не применялась — создаём здесь).
-- Удаление строк при удалении заведения: ON DELETE CASCADE от establishments.
CREATE TABLE IF NOT EXISTS public.procurement_receipt_documents (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES public.establishments(id) ON DELETE CASCADE,
  created_by_employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  recipient_chef_id UUID REFERENCES public.employees(id) ON DELETE CASCADE,
  recipient_email TEXT,
  source_order_document_id UUID REFERENCES public.order_documents(id) ON DELETE SET NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_procurement_receipt_establishment
  ON public.procurement_receipt_documents(establishment_id);
CREATE INDEX IF NOT EXISTS idx_procurement_receipt_created_at
  ON public.procurement_receipt_documents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_procurement_receipt_source_order
  ON public.procurement_receipt_documents(source_order_document_id)
  WHERE source_order_document_id IS NOT NULL;

COMMENT ON TABLE public.procurement_receipt_documents IS 'Приёмка поставок: факт, цены; строки по получателям как у order_documents.';

ALTER TABLE public.procurement_receipt_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_procurement_receipt_select" ON public.procurement_receipt_documents;
CREATE POLICY "auth_procurement_receipt_select" ON public.procurement_receipt_documents
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM public.employees WHERE id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "auth_procurement_receipt_insert" ON public.procurement_receipt_documents;
CREATE POLICY "auth_procurement_receipt_insert" ON public.procurement_receipt_documents
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM public.employees WHERE id = auth.uid()
    )
  );

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.procurement_receipt_documents;
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

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
  'Согласование изменения цен в номенклатуре (приёмка уже зафиксирована в procurement_receipt_documents). lines: [{productId, productName, unit, oldPricePerUnit, newPricePerUnit}].';

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
