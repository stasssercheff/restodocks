-- RPC для быстрой очистки номенклатуры заведения (bulk delete без возврата данных)
-- SECURITY INVOKER — RLS проверяется, удаляются только строки заведений пользователя
CREATE OR REPLACE FUNCTION clear_establishment_nomenclature(p_establishment_id uuid)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path = public
AS $$
  DELETE FROM establishment_products WHERE establishment_id = p_establishment_id;
$$;

COMMENT ON FUNCTION clear_establishment_nomenclature(uuid) IS 'Удаляет все продукты из номенклатуры заведения. Быстрый bulk delete.';

GRANT EXECUTE ON FUNCTION clear_establishment_nomenclature(uuid) TO authenticated;
