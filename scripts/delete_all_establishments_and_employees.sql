-- Полная очистка: все пользователи, заведения, сотрудники — для тестирования с нуля после переноса в Supabase
-- Выполнить в Supabase Dashboard → SQL Editor
-- ВНИМАНИЕ: Удалит ВСЁ (auth.users, employees, establishments и все связанные данные)

-- 1. Обнуляем owner_id (иначе FK при удалении employees)
UPDATE establishments SET owner_id = NULL;

-- 2. Таблицы, зависящие от employees (явно — на случай остатков от миграций)
-- (Если какой-то таблицы нет — закомментируйте строку)
TRUNCATE password_reset_tokens CASCADE;
TRUNCATE co_owner_invitations CASCADE;
TRUNCATE inventory_documents CASCADE;
TRUNCATE order_documents CASCADE;
TRUNCATE inventory_drafts CASCADE;

-- 3. Таблицы, зависящие от establishments
TRUNCATE establishment_schedule_data CASCADE;
TRUNCATE establishment_order_list_data CASCADE;
TRUNCATE product_price_history CASCADE;
TRUNCATE establishment_products CASCADE;
TRUNCATE tt_ingredients CASCADE;
TRUNCATE tech_cards CASCADE;

-- 4. Очищаем сотрудников
TRUNCATE employees CASCADE;

-- 5. Удаляем заведения
DELETE FROM establishments;

-- 6. Auth: identities и users (полный сброс для повторной регистрации)
TRUNCATE auth.identities CASCADE;
TRUNCATE auth.users CASCADE;

-- Проверка
SELECT 'employees' AS tbl, COUNT(*) AS cnt FROM employees
UNION ALL SELECT 'establishments', COUNT(*) FROM establishments
UNION ALL SELECT 'auth.users', COUNT(*) FROM auth.users;
