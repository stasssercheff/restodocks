# Правила деплоя (Beta vs Prod)

## Разделение сред

| Среда | Ветка | Деплой |
|-------|-------|--------|
| **Beta** | `staging` | Push в staging → Cloudflare Beta строит |
| **Prod** | `main` | Push в main → Cloudflare Prod строит |

## Обязательная проверка в Cloudflare

**Workers & Pages** → каждый проект → **Settings** → **Builds & deployments**:

| Проект | Production branch | Preview deployments |
|--------|-------------------|---------------------|
| Restodocks (Prod) | `main` | **None** (отключить) |
| Restodocks Beta | `staging` | **None** (отключить) |

Если оба проекта смотрят одну ветку или включены Preview — оба будут обновляться. Проверь и исправь.

## Workflow разработки

1. **Разработка** — работаем в `staging`, пушим в `staging`.
2. **Beta** — автоматически деплоится при push в `staging`.
3. **Релиз в Prod** — только когда всё проверено на Beta:
   ```bash
   git checkout main
   git merge staging
   git push origin main
   ```
4. **Никогда** не коммитить и не пушить в `main` во время разработки — иначе сырой код попадёт в Prod.

## GitHub Actions (если используются)

- **Build and Deploy to Vercel (Demo/Beta)** — checkout `staging`, деплой Beta.
- **Build and Deploy to Vercel (Production)** — checkout `main`, только ручной запуск.

## Supabase: миграции и Edge Functions

### Миграции HACCP (журналы)

Таблицы `establishment_haccp_config` и `haccp_*_logs` создаются миграциями 20260313. Если при выборе журналов ошибка 404 — применить миграции:

```bash
cd restodocks_flutter
npx supabase db push --project-ref osglfptwbuqqmqunttha
```

Либо выполнить `supabase/migrations/20260313000000_haccp_journals.sql` и `20260313100000_haccp_structured_tables.sql` вручную в SQL Editor.

### Edge Functions (ТТК-импорт)

Деплой только вручную. Требуется: `cd restodocks_flutter`, `npx supabase` (CLI установлен).

```bash
cd restodocks_flutter
npx supabase functions deploy parse-xls-bytes --project-ref osglfptwbuqqmqunttha
npx supabase functions deploy parse-ttk-by-templates --project-ref osglfptwbuqqmqunttha   # шаблоны без лимита, без AI
npx supabase functions deploy tt-parse-save-learning --project-ref osglfptwbuqqmqunttha   # обучение парсера (обход RLS)
npx supabase functions deploy ai-recognize-tech-cards-batch --project-ref osglfptwbuqqmqunttha
npx supabase functions deploy ai-parse-tech-cards-pdf --project-ref osglfptwbuqqmqunttha
npx supabase functions deploy request-change-password --project-ref osglfptwbuqqmqunttha
npx supabase functions deploy get-training-video-url --project-ref osglfptwbuqqmqunttha   # RU → Supabase Storage, остальные → YouTube
```

### Проверка импорта ТТК и обучения на Beta

Чтобы импорт ТТК и обучение работали на Beta-сайте:

1. **Задеплоены функции:**
   - `parse-ttk-by-templates` — парсинг по шаблонам (без AI)
   - `tt-parse-save-learning` — сохранение обучения (шаблоны, правки)

2. **Проверка на Beta:** ТТК → Импорт → загрузить Excel. При успехе — карточки на экране редактирования. При правке и сохранении — обучение пишется в `tt_parse_*`. Если обучение не сохранилось — SnackBar покажет «Обучение не сохранилось» и текст ошибки.
