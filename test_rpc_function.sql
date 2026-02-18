-- ТЕСТИРОВАНИЕ RPC ФУНКЦИИ get_establishment_products

-- Проверяем, существует ли функция
SELECT
  proname,
  proargnames,
  prorettype::text
FROM pg_proc
WHERE proname = 'get_establishment_products';

-- Тестируем функцию
SELECT * FROM get_establishment_products('35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'::uuid);

-- Если функция не существует, создаем её
CREATE OR REPLACE FUNCTION get_establishment_products(est_id UUID)
RETURNS TABLE (
  product_id UUID,
  price DECIMAL,
  currency TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Проверяем права доступа
  IF NOT EXISTS (
    SELECT 1 FROM establishments
    WHERE id = est_id AND owner_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Access denied or establishment not found';
  END IF;

  -- Возвращаем данные
  RETURN QUERY
  SELECT ep.product_id, ep.price, ep.currency
  FROM establishment_products ep
  WHERE ep.establishment_id = est_id;

END;
$$;

-- Предоставляем права
GRANT EXECUTE ON FUNCTION get_establishment_products(UUID) TO authenticated;

-- Тестируем снова
SELECT * FROM get_establishment_products('35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'::uuid);