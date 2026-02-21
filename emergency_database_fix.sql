-- ЭКСТРЕННОЕ ВОССТАНОВЛЕНИЕ - ПОЛНОСТЬЮ ОТКЛЮЧАЕМ RLS
-- Выполнить в Supabase SQL Editor

-- ВРЕМЕННО ОТКЛЮЧАЕМ RLS НА ВСЕХ ТАБЛИЦАХ ДЛЯ ТЕСТИРОВАНИЯ
ALTER TABLE products DISABLE ROW LEVEL SECURITY;
ALTER TABLE establishment_products DISABLE ROW LEVEL SECURITY;
ALTER TABLE employees DISABLE ROW LEVEL SECURITY;
ALTER TABLE establishments DISABLE ROW LEVEL SECURITY;
ALTER TABLE tech_cards DISABLE ROW LEVEL SECURITY;
ALTER TABLE checklists DISABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_items DISABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_submissions DISABLE ROW LEVEL SECURITY;
ALTER TABLE order_documents DISABLE ROW LEVEL SECURITY;
ALTER TABLE password_reset_tokens DISABLE ROW LEVEL SECURITY;
ALTER TABLE roles DISABLE ROW LEVEL SECURITY;
ALTER TABLE departments DISABLE ROW LEVEL SECURITY;
ALTER TABLE schedules DISABLE ROW LEVEL SECURITY;
ALTER TABLE reviews DISABLE ROW LEVEL SECURITY;
ALTER TABLE cooking_processes DISABLE ROW LEVEL SECURITY;
ALTER TABLE tt_ingredients DISABLE ROW LEVEL SECURITY;

-- ПРОВЕРЯЕМ, ЧТО МОЖЕМ ЧИТАТЬ ДАННЫЕ
SELECT COUNT(*) as products FROM products;
SELECT COUNT(*) as establishment_products FROM establishment_products;
SELECT COUNT(*) as employees FROM employees;
SELECT COUNT(*) as establishments FROM establishments;

-- ТЕСТИРУЕМ ЗАПРОСЫ
SELECT id, name, category FROM products LIMIT 5;
SELECT establishment_id, COUNT(*) as count FROM establishment_products GROUP BY establishment_id;

-- ЕСЛИ ВСЕ РАБОТАЕТ - ЗНАЧИТ ПРОБЛЕМА БЫЛА В RLS ПОЛИТИКАХ
-- ТОГДА МОЖНО ПОСТЕПЕННО ВКЛЮЧАТЬ RLS ОБРАТНО С ПРАВИЛЬНЫМИ ПОЛИТИКАМИ