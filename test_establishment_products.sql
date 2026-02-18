-- ТЕСТОВЫЙ ЗАПРОС establishment_products
-- Выполните этот запрос в Supabase SQL Editor

SELECT
  ep.product_id,
  ep.price,
  ep.currency,
  ep.establishment_id,
  e.name as establishment_name,
  e.owner_id
FROM establishment_products ep
JOIN establishments e ON ep.establishment_id = e.id
WHERE ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
  AND e.owner_id = auth.uid()
LIMIT 10;