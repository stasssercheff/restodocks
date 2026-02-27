-- Дата начала действия промокода (с какой даты можно использовать)
alter table promo_codes add column if not exists starts_at timestamptz;

-- check_promo_code: учитываем период действия (starts_at и expires_at)
create or replace function check_promo_code(p_code text)
returns text
language plpgsql
security definer
as $$
declare
  v_row promo_codes%rowtype;
begin
  select * into v_row
  from promo_codes
  where upper(trim(code)) = upper(trim(p_code));

  if not found then
    return 'invalid';
  end if;

  if v_row.is_used then
    return 'used';
  end if;

  if v_row.starts_at is not null and v_row.starts_at > now() then
    return 'not_started';
  end if;

  if v_row.expires_at is not null and v_row.expires_at < now() then
    return 'expired';
  end if;

  return 'ok';
end;
$$;

-- use_promo_code: тоже проверяем период действия
create or replace function use_promo_code(
  p_code text,
  p_establishment_id uuid
) returns text
language plpgsql
security definer
as $$
declare
  v_row promo_codes%rowtype;
begin
  select * into v_row
  from promo_codes
  where upper(trim(code)) = upper(trim(p_code))
  for update;

  if not found then
    return 'invalid';
  end if;

  if v_row.is_used then
    return 'used';
  end if;

  if v_row.starts_at is not null and v_row.starts_at > now() then
    return 'not_started';
  end if;

  if v_row.expires_at is not null and v_row.expires_at < now() then
    return 'expired';
  end if;

  update promo_codes
  set is_used = true,
      used_by_establishment_id = p_establishment_id,
      used_at = now()
  where id = v_row.id;

  return 'ok';
end;
$$;
