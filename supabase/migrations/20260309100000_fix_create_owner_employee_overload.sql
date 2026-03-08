-- PostgREST не может выбрать между двумя перегрузками create_owner_employee.
-- Удаляем старую 6-параметровую версию, оставляем 7-параметровую (с p_owner_access_level).

DROP FUNCTION IF EXISTS public.create_owner_employee(uuid, uuid, text, text, text, text[]);
