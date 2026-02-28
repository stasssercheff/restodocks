-- Лимит сотрудников на заведение (null = без ограничений)
alter table promo_codes add column if not exists max_employees integer;

-- Функция проверки: не превышен ли лимит сотрудников для заведения
-- Возвращает 'ok' или 'limit_reached'
create or replace function check_employee_limit(p_establishment_id uuid)
returns text
language plpgsql
security definer
as $$
declare
  v_max integer;
  v_count integer;
begin
  -- Берём лимит из промокода этого заведения
  select max_employees into v_max
  from promo_codes
  where used_by_establishment_id = p_establishment_id
  limit 1;

  -- Нет промокода или лимит не задан — без ограничений
  if not found or v_max is null then
    return 'ok';
  end if;

  -- Считаем активных сотрудников
  select count(*) into v_count
  from employees
  where establishment_id = p_establishment_id
    and is_active = true;

  if v_count >= v_max then
    return 'limit_reached';
  end if;

  return 'ok';
end;
$$;
