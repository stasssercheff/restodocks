-- Исправление политик для tech_cards
-- Проблема: приложение работает через анонимный доступ, но RLS требует аутентификации

-- Удаляем старые политики
DROP POLICY IF EXISTS "Users can view tech cards from their establishment" ON tech_cards;
DROP POLICY IF EXISTS "Users can manage tech cards from their establishment" ON tech_cards;

-- Временное решение: отключаем RLS для tech_cards до внедрения полноценной аутентификации
-- Это позволит приложению работать с текущей архитектурой
ALTER TABLE tech_cards DISABLE ROW LEVEL SECURITY;

-- Аналогично для tt_ingredients
DROP POLICY IF EXISTS "Users can view ingredients from their establishment" ON tt_ingredients;
DROP POLICY IF EXISTS "Users can manage ingredients from their establishment" ON tt_ingredients;
ALTER TABLE tt_ingredients DISABLE ROW LEVEL SECURITY;

-- Альтернативное решение (если хотим сохранить RLS):
-- Создать политику, которая позволяет все операции для анонимных пользователей
-- CREATE POLICY "Allow all operations for anonymous users" ON tech_cards FOR ALL USING (true);
-- CREATE POLICY "Allow all operations for anonymous users" ON tt_ingredients FOR ALL USING (true);
