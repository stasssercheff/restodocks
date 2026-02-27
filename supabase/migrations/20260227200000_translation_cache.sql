create table if not exists translation_cache (
  id            bigserial primary key,
  source_text   text        not null,
  source_lang   text        not null default 'ru',
  target_lang   text        not null default 'en',
  translated    text        not null,
  created_at    timestamptz not null default now(),
  constraint translation_cache_unique unique (source_text, source_lang, target_lang)
);

create index if not exists translation_cache_lookup
  on translation_cache (source_lang, target_lang, source_text);

alter table translation_cache enable row level security;

-- Edge Functions (service_role) могут читать и писать, обычные пользователи — нет
create policy "service_role full access"
  on translation_cache
  for all
  to service_role
  using (true)
  with check (true);
