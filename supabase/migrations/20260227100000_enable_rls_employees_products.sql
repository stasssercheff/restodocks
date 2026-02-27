-- Включаем RLS на таблицах employees и products.
-- Политики уже существуют (созданы в предыдущих миграциях),
-- но RLS не был включён — данные были полностью открыты.

ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
