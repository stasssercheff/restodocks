-- Исправление опечаток в каталоге продуктов:
-- 1. Соус Кewpie → Соус Kewpie (латинская K вместо кириллической К в бренде)
-- 2. Пасте карри → Паста карри (Паста, не Пасте)

UPDATE products
SET
  name = 'Соус Kewpie (японский майонез)',
  names = '{"ru":"Соус Kewpie (японский майонез)","en":"Kewpie mayonnaise"}'::jsonb
WHERE name = 'Соус Кewpie (японский майонез)';

UPDATE products
SET
  name = 'Паста карри Массаман',
  names = '{"ru":"Паста карри Массаман","en":"Massaman curry paste"}'::jsonb
WHERE name = 'Пасте карри Массаман';
