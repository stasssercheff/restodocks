-- Унификация RLS: единый источник — auth.uid() и auth_user_id.
-- Все политики должны использовать auth_user_id = auth.uid(), НЕ employees.id = auth.uid().
-- (employees.id — бизнес-PK, auth.users.id — идентификатор входа; связь через auth_user_id)
--
-- Удаляем политики с неправильным условием employees.id = auth.uid().
-- Они могли быть созданы setup-скриптами (final_rls_setup.sql и т.п.).

-- order_documents: блокировала INSERT/SELECT — именно она ломала заказы во входящих
DROP POLICY IF EXISTS "order_documents_establishment_access" ON order_documents;
