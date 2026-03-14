# Обучение парсера ТТК — проверка работы

## Как работает обучение

1. **tt_parse_templates** — шаблоны колонок (№, продукт, брутто, нетто…). Сохраняются при первом успешном парсинге по ключевым словам или AI.
2. **tt_parse_learned_dish_name** — выученные позиции (где название блюда, product_col, gross_col, net_col). Сохраняются при правках в импорте.
3. **tt_parse_corrections** — правки original → corrected (названия блюд). Применяются при следующем парсинге того же формата.

## Что проверить

### 1. Edge Function tt-parse-save-learning задеплоена

```bash
npx supabase functions deploy tt-parse-save-learning --project-ref osglfptwbuqqmqunttha
```

- **config.toml:** `verify_jwt = false` (legacy-логин без JWT)
- **Проверка:** В Supabase Dashboard → Edge Functions — `tt-parse-save-learning` в списке

### 2. Таблицы есть в БД

- `tt_parse_templates`
- `tt_parse_learned_dish_name`
- `tt_parse_corrections`

Миграции в `supabase/migrations/`:
- `20260318500000_tt_parse_templates.sql`
- `20260320000000_tt_parse_learned_dish_name.sql`
- `20260319000000_tt_parse_corrections.sql`

### 3. Legacy-логин (anon) и правки

Приложение читает `tt_parse_corrections` для применения правок. Для legacy-пользователей (без Supabase Auth) запрос идёт с ролью **anon**. Нужна политика `anon_select_tt_parse_corrections` — иначе правки не применяются.

Миграция `20260322100000_tt_parse_corrections_anon_select.sql` добавляет эту политику.

### 4. При сохранении импорта

- В SnackBar: `ttk_learn_error_hint` — значит обучение не сохранилось.
- `AiServiceSupabase.lastLearningError` — последняя ошибка (можно смотреть в devLog).

### 5. Логи Edge Function

Supabase Dashboard → Edge Functions → `tt-parse-save-learning` → Logs:

- `body keys: template` или `learned_dish_name` или `correction` — запрос дошёл
- `template upsert error` / `learned_dish_name upsert error` — ошибка записи

## Парсинг не трогаем

Изменения в этом документе и связанных миграциях **не меняют** логику парсинга (`parse_ttk_template.ts`, `try_stored_ttk_templates.ts`, `ai-recognize-tech-cards-batch`). Только доступ к данным обучения.
