-- Phase 3: POS / склад / журнал ошибок / заявки ТТК — убрать anon ALL, сузить authenticated по tenant.
-- Клиент Flutter ходит с JWT (authenticated). RPC SECURITY DEFINER и Edge (service_role) обходят RLS как задумано.
-- Опасные политики public+true на employees и allow_all на establishment_products — дроп при наличии.

-- ---------------------------------------------------------------------------
-- 0) Снять политики «всё всем», если остались от ручных правок / старых веток
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS allow_all_establishment_products ON public.establishment_products;

DROP POLICY IF EXISTS employees_select ON public.employees;
DROP POLICY IF EXISTS employees_insert ON public.employees;
DROP POLICY IF EXISTS employees_update ON public.employees;
DROP POLICY IF EXISTS employees_delete ON public.employees;

-- ---------------------------------------------------------------------------
-- 1) pos_dining_tables (establishment_id)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_pos_dining_tables_all ON public.pos_dining_tables;
DROP POLICY IF EXISTS auth_pos_dining_tables_all ON public.pos_dining_tables;

CREATE POLICY auth_pos_dining_tables_all ON public.pos_dining_tables
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 2) pos_orders (establishment_id)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_pos_orders_all ON public.pos_orders;
DROP POLICY IF EXISTS auth_pos_orders_all ON public.pos_orders;

CREATE POLICY auth_pos_orders_all ON public.pos_orders
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 3) pos_order_lines (через pos_orders)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_pos_order_lines_all ON public.pos_order_lines;
DROP POLICY IF EXISTS auth_pos_order_lines_all ON public.pos_order_lines;

CREATE POLICY auth_pos_order_lines_all ON public.pos_order_lines
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_orders o
      WHERE o.id = pos_order_lines.order_id
        AND o.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.pos_orders o
      WHERE o.id = pos_order_lines.order_id
        AND o.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  );

-- ---------------------------------------------------------------------------
-- 4) pos_order_payments (через pos_orders)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_pos_order_payments_all ON public.pos_order_payments;
DROP POLICY IF EXISTS auth_pos_order_payments_all ON public.pos_order_payments;

CREATE POLICY auth_pos_order_payments_all ON public.pos_order_payments
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_orders o
      WHERE o.id = pos_order_payments.order_id
        AND o.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.pos_orders o
      WHERE o.id = pos_order_payments.order_id
        AND o.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  );

-- ---------------------------------------------------------------------------
-- 5) pos_cash_shifts, pos_cash_disbursements (establishment_id)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_pos_cash_shifts_all ON public.pos_cash_shifts;
DROP POLICY IF EXISTS auth_pos_cash_shifts_all ON public.pos_cash_shifts;

CREATE POLICY auth_pos_cash_shifts_all ON public.pos_cash_shifts
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

DROP POLICY IF EXISTS anon_pos_cash_disbursements_all ON public.pos_cash_disbursements;
DROP POLICY IF EXISTS auth_pos_cash_disbursements_all ON public.pos_cash_disbursements;

CREATE POLICY auth_pos_cash_disbursements_all ON public.pos_cash_disbursements
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 6) establishment_stock_balances, establishment_stock_movements
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_establishment_stock_balances_all ON public.establishment_stock_balances;
DROP POLICY IF EXISTS auth_establishment_stock_balances_all ON public.establishment_stock_balances;

CREATE POLICY auth_establishment_stock_balances_all ON public.establishment_stock_balances
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

DROP POLICY IF EXISTS anon_establishment_stock_movements_all ON public.establishment_stock_movements;
DROP POLICY IF EXISTS auth_establishment_stock_movements_all ON public.establishment_stock_movements;

CREATE POLICY auth_establishment_stock_movements_all ON public.establishment_stock_movements
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 7) tech_card_change_requests (establishment_id)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_tech_card_change_requests_all ON public.tech_card_change_requests;
DROP POLICY IF EXISTS auth_tech_card_change_requests_all ON public.tech_card_change_requests;

CREATE POLICY auth_tech_card_change_requests_all ON public.tech_card_change_requests
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 8) system_errors — anon убрать; authenticated только по своему заведению
--    Вставка с Edge (service_role) по-прежнему без RLS.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_system_errors_all ON public.system_errors;
DROP POLICY IF EXISTS auth_system_errors_all ON public.system_errors;

CREATE POLICY auth_system_errors_all ON public.system_errors
  FOR ALL TO authenticated
  USING (
    establishment_id IS NOT NULL
    AND establishment_id IN (SELECT public.current_user_establishment_ids())
  )
  WITH CHECK (
    establishment_id IS NOT NULL
    AND establishment_id IN (SELECT public.current_user_establishment_ids())
  );
