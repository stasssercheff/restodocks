-- PostgREST не может выбрать между двумя перегрузками create_employee_for_company.
-- Удаляем старую 8-параметровую версию (без p_owner_access_level), оставляем 9-параметровую.

DROP FUNCTION IF EXISTS public.create_employee_for_company(uuid, uuid, text, text, text, text, text, text[]);
