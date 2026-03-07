-- Применить в Supabase SQL Editor для ускорения очистки номенклатуры

CREATE OR REPLACE FUNCTION clear_establishment_nomenclature(p_establishment_id uuid)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path = public
AS $$
  DELETE FROM establishment_products WHERE establishment_id = p_establishment_id;
$$;

GRANT EXECUTE ON FUNCTION clear_establishment_nomenclature(uuid) TO authenticated;
