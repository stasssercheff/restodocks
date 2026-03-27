create table if not exists public.user_policy_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  policy_type text not null default 'privacy_policy',
  policy_version text not null,
  accepted_at timestamptz not null default now(),
  locale text,
  ip_address text,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_policy_consents_unique unique (user_id, policy_type, policy_version)
);

alter table public.user_policy_consents enable row level security;

create policy user_policy_consents_select_own
on public.user_policy_consents
for select
to authenticated
using (auth.uid() = user_id);

create policy user_policy_consents_insert_own
on public.user_policy_consents
for insert
to authenticated
with check (auth.uid() = user_id);

create policy user_policy_consents_update_own
on public.user_policy_consents
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create or replace function public.tg_user_policy_consents_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_user_policy_consents_updated_at on public.user_policy_consents;
create trigger trg_user_policy_consents_updated_at
before update on public.user_policy_consents
for each row
execute function public.tg_user_policy_consents_updated_at();
