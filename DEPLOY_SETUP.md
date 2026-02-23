# Настройка автодеплоя Restodocks

Деплой выполняется через GitHub Actions при push в `main` или `master`.

## Секреты в GitHub

Репозиторий → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

Добавьте:

| Секрет | Описание |
|--------|----------|
| `VERCEL_TOKEN` | Vercel → Account Settings → Tokens → Create Token |
| `VERCEL_ORG_ID` | `team_l4N4pAZyq8RCmMOLAqatxkUn` |
| `VERCEL_PROJECT_ID` | `prj_4FMDqFFqx73cJSoap5uMyO6QSuG2` |
| `SUPABASE_URL` | Supabase → Project Settings → API → Project URL |
| `SUPABASE_ANON_KEY` | Supabase → Project Settings → API → anon public key |

## Проверка

1. Добавьте секреты
2. Сделайте `git push` в ветку `main` (или `master`)
3. GitHub → **Actions** → запустится workflow «Build and Deploy to Vercel»
4. После успешного завершения сайт обновится на restodocks.com
