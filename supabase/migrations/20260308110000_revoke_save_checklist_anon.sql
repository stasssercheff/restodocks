-- Все действия — сотрудники под учётной записью, анонимных нет. Убираем лишний GRANT.
REVOKE EXECUTE ON FUNCTION public.save_checklist FROM anon;
