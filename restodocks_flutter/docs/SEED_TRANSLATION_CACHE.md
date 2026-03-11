# translation_cache — каталог переводов

**translation_cache** — единый каталог пар (source_text, source_lang, target_lang, translated) для переиспользования и машинного обучения.

## Откуда попадают переводы

1. **Edge Functions** (translate-text, auto-translate-product) — DeepL, результат пишется в translation_cache.
2. **TranslationService** (MyMemory, AI) — сохраняет в таблицу `translations`, триггер `tr_translations_sync_to_cache` дублирует в translation_cache.

Таким образом все новые переводы попадают в каталог для будущего использования (ML, префилл, экспорт).

---

# Предзаполнение translation_cache (без расхода DeepL)

Чтобы не тратить лимиты DeepL на перевод названий продуктов, можно один раз предзаполнить таблицу `translation_cache` переводами RU/EN/ES → TR через бесплатный MyMemory API.

## Как это работает

1. **translation_cache** — таблица в Supabase, в которую Edge Functions (translate-text, auto-translate-product) смотрят **до** вызова DeepL.
2. Если перевод найден в кэше — DeepL не вызывается.
3. Скрипт переводит названия продуктов из world_products.json через MyMemory и генерирует SQL.

## Запуск

```bash
cd restodocks_flutter
pip install deep-translator   # если ещё нет
python3 scripts/seed_translation_cache_products.py
```

Скрипт создаст файл `seed_translation_cache.sql`.

## Применение

1. Откройте **Supabase Dashboard** → **SQL Editor**
2. Вставьте содержимое `seed_translation_cache.sql`
3. Выполните

После этого переводы продуктов будут браться из кэша, DeepL — только для новых/неизвестных текстов.

## auto-translate-product

В Edge Function `auto-translate-product` добавлен язык `tr` в SUPPORTED_LANGS — батч-перевод продуктов теперь включает турецкий.
