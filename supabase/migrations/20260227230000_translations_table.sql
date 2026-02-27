-- Таблица переводов динамического контента (продукты, ТТК, чеклисты)
create table if not exists translations (
  id                bigserial primary key,
  entity_type       text        not null,
  entity_id         text        not null,
  field_name        text        not null,
  source_text       text        not null,
  source_language   text        not null default 'ru',
  target_language   text        not null,
  translated_text   text        not null,
  is_manual_override boolean    not null default false,
  created_at        timestamptz not null default now(),
  created_by        text,
  constraint translations_unique unique (entity_type, entity_id, field_name, source_language, target_language)
);

create index if not exists translations_entity_idx
  on translations (entity_type, entity_id, field_name);

-- RLS: читать может любой аутентифицированный, писать — тоже
alter table translations enable row level security;

create policy "translations_select" on translations
  for select using (auth.role() = 'authenticated');

create policy "translations_insert" on translations
  for insert with check (auth.role() = 'authenticated');

create policy "translations_update" on translations
  for update using (auth.role() = 'authenticated');

-- service_role имеет полный доступ автоматически
