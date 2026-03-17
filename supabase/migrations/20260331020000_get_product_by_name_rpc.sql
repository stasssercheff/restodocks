-- RPC для поиска продукта по нормализованному имени (lower(trim)).
-- Используется при 409 Conflict: продукт уже есть в БД, ищем его для маппинга ингредиентов.
CREATE OR REPLACE FUNCTION get_product_by_normalized_name(p_name text)
RETURNS products AS $$
  SELECT * FROM products WHERE lower(trim(name)) = lower(trim(p_name)) LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_product_by_normalized_name(text) TO authenticated;
