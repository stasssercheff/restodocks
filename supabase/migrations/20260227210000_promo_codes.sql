create table if not exists promo_codes (
  id            bigserial primary key,
  code          text        not null unique,
  is_used       boolean     not null default false,
  used_by_establishment_id uuid references establishments(id) on delete set null,
  used_at       timestamptz,
  created_at    timestamptz not null default now(),
  note          text
);

alter table promo_codes enable row level security;

-- Только service_role может читать и писать (владелец вносит коды напрямую через Supabase Dashboard)
create policy "service_role full access"
  on promo_codes for all
  to service_role
  using (true)
  with check (true);

-- RPC: проверить промокод и пометить как использованный
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

  update promo_codes
  set is_used = true,
      used_by_establishment_id = p_establishment_id,
      used_at = now()
  where id = v_row.id;

  return 'ok';
end;
$$;

-- RPC: только проверить промокод без использования (валидация на форме)
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

  return 'ok';
end;
$$;
