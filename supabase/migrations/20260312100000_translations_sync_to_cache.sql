-- Синхронизация переводов в translation_cache для единого каталога (машинное обучение).
-- Все новые переводы (из translations — MyMemory, AI, или сохранённые клиентом) попадают в translation_cache.

create or replace function sync_translation_to_cache()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into translation_cache (source_text, source_lang, target_lang, translated)
  values (
    new.source_text,
    coalesce(new.source_language, 'ru'),
    new.target_language,
    new.translated_text
  )
  on conflict (source_text, source_lang, target_lang)
  do update set translated = excluded.translated;
  return new;
end;
$$;

drop trigger if exists tr_translations_sync_to_cache on translations;
create trigger tr_translations_sync_to_cache
  after insert on translations
  for each row
  execute function sync_translation_to_cache();
