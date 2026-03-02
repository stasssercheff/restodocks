-- Добавляем поле sheet_name в iiko_products (название листа Excel)
ALTER TABLE iiko_products
  ADD COLUMN IF NOT EXISTS sheet_name TEXT;

-- Добавляем поля для хранения информации о листах в метаданных бланка
ALTER TABLE iiko_blank_meta
  ADD COLUMN IF NOT EXISTS sheet_names JSONB,
  ADD COLUMN IF NOT EXISTS sheet_qty_cols JSONB;

-- Обновляем RPC insert_iiko_products чтобы принимала sheet_name
CREATE OR REPLACE FUNCTION insert_iiko_products(p_items JSONB)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO iiko_products (
    id, establishment_id, code, name, unit, group_name, sort_order, sheet_name
  )
  SELECT
    gen_random_uuid(),
    (item->>'establishment_id')::uuid,
    item->>'code',
    item->>'name',
    item->>'unit',
    item->>'group_name',
    (item->>'sort_order')::int,
    item->>'sheet_name'
  FROM jsonb_array_elements(p_items) AS item;
END;
$$;
