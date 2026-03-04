# Бэкап перед внедрением RPC-защиты регистрации (04.03.2026)

## ✅ Что уже сделано

1. **Git-тег** — точка отката кода:
   ```bash
   git tag -l "backup-before-rpc*"
   git checkout backup-before-rpc-20260304-1647  # откат к бэкапу
   ```

2. **Архив кода** — `backups/backup_20260304_164746/`:
   - `code/` — весь проект
   - `supabase_config/` — миграции, функции
   - `ВОССТАНОВИТЬ.sh` — инструкции восстановления

## ⚠️ Бэкап БД — нужно сделать вручную

`backup_config.env` отсутствует, поэтому дамп БД не выполнялся.

### Вариант 1: Через Supabase Dashboard (самый простой)

1. Откройте [Supabase Dashboard](https://app.supabase.com) → ваш проект
2. **Database** → **Backups** — Supabase хранит ежедневные бэкапы
3. При необходимости можно сделать **Point-in-Time Recovery** до нужного момента

### Вариант 2: Через pg_dump (полный дамп)

1. Создайте `backup_config.env`:
   ```bash
   cp backup_config.env.example backup_config.env
   # Отредактируйте: вставьте пароль БД из Supabase → Settings → Database
   ```

2. Повторно запустите бэкап:
   ```bash
   ./backup_all.sh
   ```

3. В `backups/backup_*/` появится `database.sql.gz`

### Вариант 3: Через Supabase CLI

```bash
supabase db dump --db-url 'postgresql://postgres:ПАРОЛЬ@db.osglfptwbuqqmqunttha.supabase.co:5432/postgres' > database_backup_$(date +%Y%m%d).sql
gzip database_backup_*.sql
```

## Порядок деплоя RPC-защиты

1. **Сначала** применить миграцию в Supabase (SQL Editor или `supabase db push`)
2. **Потом** задеплоить Flutter и beta-admin (push в main/staging)

Если деплоить в обратном порядке — регистрация сломается до применения миграции.

## Откат после RPC-изменений

Если что-то пойдёт не так:

```bash
git checkout backup-before-rpc-20260304-1647
# или
git revert <коммиты с RPC>
```

Восстановление БД: `gunzip -c database.sql.gz | psql "$SUPABASE_DB_URL"`
