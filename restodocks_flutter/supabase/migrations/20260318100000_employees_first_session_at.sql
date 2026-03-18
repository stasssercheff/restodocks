-- Признак «была хотя бы одна сессия» в этой учётной записи.
-- Окно «Начало работы» показываем только если first_session_at IS NULL (никогда не входил).

ALTER TABLE public.employees
ADD COLUMN IF NOT EXISTS first_session_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

-- У всех существующих сотрудников считаем, что сессия уже была — окно не показываем.
UPDATE public.employees
SET first_session_at = COALESCE(created_at, now())
WHERE first_session_at IS NULL;
