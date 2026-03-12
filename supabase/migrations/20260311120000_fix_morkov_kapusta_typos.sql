-- Исправление опечаток и сокращений в каталоге:
-- МокровьVND → Морковь, Купуста Б/К → Капуста белокочанная, Купуста К/К → Капуста краснокочанная

UPDATE products
SET name = 'Морковь',
    names = '{"ru":"Морковь","en":"Carrot"}'::jsonb
WHERE name = 'МокровьVND' OR name ~ 'Мокровь\s*VND';

UPDATE products
SET name = 'Капуста белокочанная',
    names = '{"ru":"Капуста белокочанная","en":"White cabbage"}'::jsonb
WHERE name = 'Купуста Б/К';

UPDATE products
SET name = 'Капуста краснокочанная',
    names = '{"ru":"Капуста краснокочанная","en":"Red cabbage"}'::jsonb
WHERE name = 'Купуста К/К';
