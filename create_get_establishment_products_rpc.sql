-- Создаем RPC функцию для получения продуктов заведения (обход RLS проблем)

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
  -- Проверяем, что пользователь является владельцем заведения
  IF NOT EXISTS (
    SELECT 1 FROM establishments
    WHERE id = est_id AND owner_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Access denied: user is not the owner of this establishment';
  END IF;

  -- Возвращаем продукты заведения
  RETURN QUERY
  SELECT ep.product_id, ep.price, ep.currency
  FROM establishment_products ep
  WHERE ep.establishment_id = est_id;

END;
$$;

-- Предоставляем права на выполнение функции
GRANT EXECUTE ON FUNCTION get_establishment_products(UUID) TO authenticated;

-- Проверяем, что функция создана
SELECT proname, proargnames, prorettype
FROM pg_proc
WHERE proname = 'get_establishment_products';