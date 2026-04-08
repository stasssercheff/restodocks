-- Разрешить обновление payload приёмки (подтверждение руководством и т.п.).
DROP POLICY IF EXISTS "auth_procurement_receipt_update" ON public.procurement_receipt_documents;
CREATE POLICY "auth_procurement_receipt_update" ON public.procurement_receipt_documents
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
