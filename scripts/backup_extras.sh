#!/bin/bash
# Бэкап частей, не входящих в код: Vercel env, Supabase Auth чеклист
# Вызывается из backup_all.sh

BACKUP_DIR="${1:-.}"
mkdir -p "$BACKUP_DIR"

echo "   📋 Vercel env..."
if command -v vercel >/dev/null 2>&1; then
    vercel env pull .env.vercel.backup 2>/dev/null && mv .env.vercel.backup "$BACKUP_DIR/vercel_env.env" 2>/dev/null || true
fi
[ ! -f "$BACKUP_DIR/vercel_env.env" ] && echo "   (vercel CLI не настроен — скопируйте env вручную из Vercel Dashboard)"

echo "   📋 Supabase Auth checklist..."
cat > "$BACKUP_DIR/SUPABASE_AUTH_CHECKLIST.md" << 'EOF'
# Supabase Auth — что проверить при сбое входа

## 1. Authentication > Providers > Email
- Enable Email: ON
- Confirm email: по необходимости
- Secure email change: по необходимости

## 2. Authentication > URL Configuration
- Site URL: https://ваш-домен.vercel.app
- Redirect URLs: добавить все домены (prod, preview)

## 3. Authentication > Email Templates
- Confirm signup, Reset password — проверить шаблоны
- Ссылки должны вести на ваш фронт

## 4. Database > RLS
- employees: anon_select_employees (SELECT TO anon USING true) — для legacy входа
- establishments: anon_select_establishments — для получения заведения после входа

## 5. Таблица employees
- password_hash: NULL для Auth-пользователей, BCrypt/$2a$ для legacy
- auth_user_id: UUID из auth.users или NULL для legacy
- is_active: true для активных

## 6. Восстановление из бэкапа БД
Если в archive есть database.sql.gz — он содержит employees, auth.users, RLS.
Восстановить: gunzip -c database.sql.gz | psql "$SUPABASE_DB_URL"
EOF
echo "   ✅ Создан SUPABASE_AUTH_CHECKLIST.md"
