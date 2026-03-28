-- Демо-столы для каждого заведения, у которого ещё нет строк в pos_dining_tables.
-- Не требует вручную подставлять establishment_id: берётся из таблицы establishments.
INSERT INTO pos_dining_tables (
  establishment_id,
  floor_name,
  room_name,
  table_number,
  sort_order,
  status
)
SELECT
  e.id,
  '1',
  'Основной',
  gs.n::int,
  (gs.n - 1)::int,
  'free'
FROM establishments e
CROSS JOIN generate_series(1, 3) AS gs(n)
WHERE NOT EXISTS (
  SELECT 1 FROM pos_dining_tables p WHERE p.establishment_id = e.id
);

COMMENT ON TABLE pos_dining_tables IS 'Столы заведения. После первой миграции с seed у каждого заведения без столов добавляются 3 демо-стола (этаж 1, зал «Основной»).';
