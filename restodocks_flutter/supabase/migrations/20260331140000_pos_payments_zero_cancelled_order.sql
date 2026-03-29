-- Нулевая сумма платежа при нулевом чеке (блюда без цены в меню) + статус отмены заказа.

ALTER TABLE pos_order_payments DROP CONSTRAINT IF EXISTS pos_order_payments_amount_check;
ALTER TABLE pos_order_payments
  ADD CONSTRAINT pos_order_payments_amount_check CHECK (amount >= 0);

COMMENT ON CONSTRAINT pos_order_payments_amount_check ON pos_order_payments IS
  'Сумма платежа может быть 0 при нулевом итоге счёта.';

ALTER TABLE pos_orders DROP CONSTRAINT IF EXISTS pos_orders_status_check;
ALTER TABLE pos_orders
  ADD CONSTRAINT pos_orders_status_check
  CHECK (status IN ('draft', 'sent', 'closed', 'cancelled'));

COMMENT ON COLUMN pos_orders.status IS
  'draft | sent | closed | cancelled (отмена без оплаты, стол освобождён).';
