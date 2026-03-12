-- Запустить в Supabase: Dashboard → SQL Editor → New query → вставить и Run
-- Исправляет опечатки в каталоге продуктов

-- 1. Юzu → Юзу (и names.en для поиска по "Yuzu juice")
UPDATE products
SET name = 'Юзу сок',
    names = jsonb_build_object('ru', 'Юзу сок', 'en', 'Yuzu juice')
WHERE name = 'Юzu сок';

-- 2. Кewpie → Kewpie
UPDATE products
SET
  name = 'Соус Kewpie (японский майонез)',
  names = '{"ru":"Соус Kewpie (японский майонез)","en":"Kewpie mayonnaise"}'::jsonb
WHERE name = 'Соус Кewpie (японский майонез)';

-- 3. Пасте → Паста
UPDATE products
SET
  name = 'Паста карри Массаман',
  names = '{"ru":"Паста карри Массаман","en":"Massaman curry paste"}'::jsonb
WHERE name = 'Пасте карри Массаман';

-- 4. МокровьVND → Морковь (carrot)
UPDATE products
SET name = 'Морковь',
    names = '{"ru":"Морковь","en":"Carrot"}'::jsonb
WHERE name = 'МокровьVND' OR name = 'Мокровь	VND';

-- 5. Купуста Б/К → Капуста белокочанная (Б/К = белокочанная)
UPDATE products
SET name = 'Капуста белокочанная',
    names = '{"ru":"Капуста белокочанная","en":"White cabbage"}'::jsonb
WHERE name = 'Купуста Б/К';

-- 6. Купуста К/К → Капуста краснокочанная (К/К = краснокочанная)
UPDATE products
SET name = 'Капуста краснокочанная',
    names = '{"ru":"Капуста краснокочанная","en":"Red cabbage"}'::jsonb
WHERE name = 'Купуста К/К';
