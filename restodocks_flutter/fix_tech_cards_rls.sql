-- ИСПРАВЛЕНИЕ ПРОБЛЕМЫ С СОХРАНЕНИЕМ ТТК
-- Выполните этот SQL в Supabase Dashboard -> SQL Editor

-- Отключаем RLS для таблиц tech_cards и tt_ingredients
-- Это временное решение до внедрения полноценной аутентификации

ALTER TABLE tech_cards DISABLE ROW LEVEL SECURITY;
ALTER TABLE tt_ingredients DISABLE ROW LEVEL SECURITY;

-- Проверяем, что изменения применились
SELECT schemaname, tablename, rowsecurity 
FROM pg_tables 
WHERE tablename IN ('tech_cards', 'tt_ingredients') 
AND schemaname = 'public';

-- Если нужно включить RLS обратно позже, выполните:
-- ALTER TABLE tech_cards ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE tt_ingredients ENABLE ROW LEVEL SECURITY;
