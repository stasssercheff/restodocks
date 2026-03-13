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

## Supabase Edge Functions (ТТК-импорт)

Деплой только вручную. Требуется: `cd restodocks_flutter`, `npx supabase` (CLI установлен).

```bash
cd restodocks_flutter
npx supabase functions deploy parse-xls-bytes --project-ref osglfptwbuqqmqunttha
npx supabase functions deploy parse-ttk-by-templates --project-ref osglfptwbuqqmqunttha   # шаблоны без лимита, без AI
npx supabase functions deploy ai-recognize-tech-cards-batch --project-ref osglfptwbuqqmqunttha
npx supabase functions deploy ai-parse-tech-cards-pdf --project-ref osglfptwbuqqmqunttha
```
