-- Исправление опечаток и сокращений в каталоге:
-- МокровьVND → Морковь, Купуста Б/К → Капуста белокочанная, Купуста К/К → Капуста краснокочанная
-- Выполняем UPDATE только если целевое имя ещё не занято (идемпотентность).

UPDATE products p1
SET name = 'Морковь',
    names = '{"ru":"Морковь","en":"Carrot"}'::jsonb
WHERE (p1.name = 'МокровьVND' OR p1.name ~ 'Мокровь\s*VND')
  AND NOT EXISTS (SELECT 1 FROM products p2 WHERE lower(trim(p2.name)) = 'морковь' AND p2.id != p1.id);

UPDATE products p1
SET name = 'Капуста белокочанная',
    names = '{"ru":"Капуста белокочанная","en":"White cabbage"}'::jsonb
WHERE p1.name = 'Купуста Б/К'
  AND NOT EXISTS (SELECT 1 FROM products p2 WHERE lower(trim(p2.name)) = 'капуста белокочанная' AND p2.id != p1.id);

UPDATE products p1
SET name = 'Капуста краснокочанная',
    names = '{"ru":"Капуста краснокочанная","en":"Red cabbage"}'::jsonb
WHERE p1.name = 'Купуста К/К'
  AND NOT EXISTS (SELECT 1 FROM products p2 WHERE lower(trim(p2.name)) = 'капуста краснокочанная' AND p2.id != p1.id);
