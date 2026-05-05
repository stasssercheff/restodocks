-- Owner-defined audience preset for POS shift closing report.
-- Snapshot of applied audience is stored in pos_cash_shifts on close.

alter table public.pos_cash_shifts
  add column if not exists close_report_scope text
    check (close_report_scope in ('all', 'zones')),
  add column if not exists close_report_zones text[] not null default '{}';

create table if not exists public.pos_shift_report_audience_settings (
  establishment_id uuid primary key references public.establishments(id) on delete cascade,
  scope text not null default 'all'
    check (scope in ('all', 'zones')),
  zones text[] not null default '{}'::text[],
  updated_by_employee_id uuid references public.employees(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.pos_shift_report_audience_settings enable row level security;

drop policy if exists pos_shift_report_audience_select on public.pos_shift_report_audience_settings;
create policy pos_shift_report_audience_select
on public.pos_shift_report_audience_settings
for select
to authenticated
using (establishment_id in (select public.current_user_establishment_ids()));

drop policy if exists pos_shift_report_audience_insert_owner on public.pos_shift_report_audience_settings;
create policy pos_shift_report_audience_insert_owner
on public.pos_shift_report_audience_settings
for insert
to authenticated
with check (
  establishment_id in (select public.current_user_establishment_ids())
  and exists (
    select 1
    from public.employees e
    where e.id = auth.uid()
      and e.establishment_id = pos_shift_report_audience_settings.establishment_id
      and coalesce(e.is_active, true)
      and 'owner' = any(coalesce(e.roles, '{}'::text[]))
  )
);

drop policy if exists pos_shift_report_audience_update_owner on public.pos_shift_report_audience_settings;
create policy pos_shift_report_audience_update_owner
on public.pos_shift_report_audience_settings
for update
to authenticated
using (
  establishment_id in (select public.current_user_establishment_ids())
  and exists (
    select 1
    from public.employees e
    where e.id = auth.uid()
      and e.establishment_id = pos_shift_report_audience_settings.establishment_id
      and coalesce(e.is_active, true)
      and 'owner' = any(coalesce(e.roles, '{}'::text[]))
  )
)
with check (
  establishment_id in (select public.current_user_establishment_ids())
  and exists (
    select 1
    from public.employees e
    where e.id = auth.uid()
      and e.establishment_id = pos_shift_report_audience_settings.establishment_id
      and coalesce(e.is_active, true)
      and 'owner' = any(coalesce(e.roles, '{}'::text[]))
  )
);

drop policy if exists pos_shift_report_audience_delete_owner on public.pos_shift_report_audience_settings;
create policy pos_shift_report_audience_delete_owner
on public.pos_shift_report_audience_settings
for delete
to authenticated
using (
  establishment_id in (select public.current_user_establishment_ids())
  and exists (
    select 1
    from public.employees e
    where e.id = auth.uid()
      and e.establishment_id = pos_shift_report_audience_settings.establishment_id
      and coalesce(e.is_active, true)
      and 'owner' = any(coalesce(e.roles, '{}'::text[]))
  )
);

drop trigger if exists trg_pos_shift_report_audience_settings_updated_at
  on public.pos_shift_report_audience_settings;
create trigger trg_pos_shift_report_audience_settings_updated_at
before update on public.pos_shift_report_audience_settings
for each row
execute function public.set_updated_at();
