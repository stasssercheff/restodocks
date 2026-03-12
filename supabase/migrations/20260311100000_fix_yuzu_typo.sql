-- Исправление опечатки: Юzu → Юзу (латинская z вместо кириллической з)
UPDATE products
SET name = 'Юзу сок',
    names = jsonb_set(names, '{ru}', '"Юзу сок"')
WHERE name = 'Юzu сок';
