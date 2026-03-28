-- Стартовая раскладка: один стол (этаж «1», зал «Основной»). Раньше seed создавал три демо-стола.
DELETE FROM pos_dining_tables
WHERE table_number IN (2, 3)
  AND floor_name IS NOT DISTINCT FROM '1'
  AND room_name IS NOT DISTINCT FROM 'Основной';

COMMENT ON TABLE pos_dining_tables IS 'Столы заведения: этаж и зал — произвольные подписи (настраивает владелец / управляющий зала). По умолчанию один стол.';
