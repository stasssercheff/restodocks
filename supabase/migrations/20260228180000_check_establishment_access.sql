-- Проверка доступа заведения по промокоду
-- Возвращает 'ok' если промокод действует, 'expired' если истёк, 'no_promo' если промокода нет
create or replace function check_establishment_access(p_establishment_id uuid)
returns text
language plpgsql
security definer
as $$
declare
  v_row promo_codes%rowtype;
begin
  select * into v_row
  from promo_codes
  where used_by_establishment_id = p_establishment_id
  limit 1;

  -- Нет промокода — доступ разрешён (старые заведения без промокода)
  if not found then
    return 'ok';
  end if;

  -- Есть expires_at и он уже прошёл
  if v_row.expires_at is not null and v_row.expires_at < now() then
    return 'expired';
  end if;

  return 'ok';
end;
$$;
