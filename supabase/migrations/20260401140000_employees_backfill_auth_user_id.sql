-- Владелец / самопрофиль: RLS auth_update_employees требует id = auth.uid() ИЛИ auth_user_id = auth.uid().
-- Старые строки после веток без auth_user_id в INSERT остаются с NULL → UPDATE даёт 0 строк.
-- Заполняем auth_user_id там, где id совпадает с пользователем Supabase Auth.

UPDATE public.employees e
SET auth_user_id = e.id
WHERE e.auth_user_id IS NULL
  AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = e.id);
