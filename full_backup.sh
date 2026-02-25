#!/bin/bash
set -e

# Полный бэкап проекта Restodocks
# Включает: код, базу данных Supabase, storage, конфигурацию
# Если вызван из backup_all.sh — использует BACKUP_TARGET_DIR

BACKUP_DIR="${BACKUP_TARGET_DIR:-backup_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$BACKUP_DIR"
echo "📁 Создаю директорию бэкапа: $BACKUP_DIR"

# 1. Бэкап кода из GitHub (уже знаете, но добавим автоматизацию)
echo "📦 Бэкап репозитория..."
git clone https://github.com/stasssercheff/restodocks.git "$BACKUP_DIR/code" --depth 1
echo "✅ Код сохранен в $BACKUP_DIR/code"

# 2. Бэкап базы данных Supabase
echo "🗄️ Бэкап базы данных Supabase..."
echo "Для бэкапа базы данных выполните в терминале Supabase CLI:"
echo "supabase db dump --db-url 'postgresql://postgres:[YOUR-PASSWORD]@db.osglfptwbuqqmqunttha.supabase.co:5432/postgres' > $BACKUP_DIR/database.sql"
echo "ИЛИ через pg_dump:"
echo "pg_dump 'postgresql://postgres:[YOUR-PASSWORD]@db.osglfptwbuqqmqunttha.supabase.co:5432/postgres' > $BACKUP_DIR/database.sql"
echo "⚠️  Вам нужно получить пароль базы данных из Supabase Dashboard > Settings > Database"

# 3. Бэкап Supabase Storage
echo "💾 Бэкап файлового хранилища..."
echo "Для бэкапа storage используйте Supabase CLI:"
echo "supabase storage ls --project-ref osglfptwbuqqmqunttha > $BACKUP_DIR/storage_files.txt"
echo "supabase storage download --project-ref osglfptwbuqqmqunttha [bucket-name] $BACKUP_DIR/storage_backup/"
echo "⚠️  Проверьте доступные бакеты в Supabase Dashboard > Storage"

# 4. Бэкап конфигурации Supabase
echo "⚙️ Бэкап конфигурации Supabase..."
mkdir -p "$BACKUP_DIR/supabase_config"

# Сохраняем миграции
cp -r restodocks_flutter/supabase/migrations "$BACKUP_DIR/supabase_config/" 2>/dev/null || echo "Миграции не найдены"

# Сохраняем функции
cp -r restodocks_flutter/supabase/functions "$BACKUP_DIR/supabase_config/" 2>/dev/null || echo "Функции не найдены"

# Сохраняем SQL файлы
find . -name "supabase*.sql" -exec cp {} "$BACKUP_DIR/supabase_config/" \; 2>/dev/null || echo "SQL файлы не найдены"

echo "✅ Конфигурация Supabase сохранена в $BACKUP_DIR/supabase_config"

# 5. Бэкап переменных окружения
echo "🔐 Бэкап переменных окружения..."
cp .env "$BACKUP_DIR/environment.env" 2>/dev/null || echo "Файл .env не найден"
echo "✅ Переменные окружения сохранены в $BACKUP_DIR/environment.env"

# 6. Бэкап настроек Vercel
echo "🚀 Бэкап настроек Vercel..."
cat > "$BACKUP_DIR/vercel_config.md" << 'EOF'
# Настройки Vercel для восстановления

## Переменные окружения (Project Settings > Environment Variables):
SUPABASE_URL=https://osglfptwbuqqmqunttha.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE

## Build Settings:
Build Command: ./vercel-build.sh
Output Directory: build/web
Install Command: (по умолчанию)
Framework Preset: (не указан)

## Deploy Hooks:
URL: https://api.vercel.com/v1/integrations/deploy/prj_4FMDqFFqx73cJSoap5uMyO6QSuG2/mmzEGXWRmk
EOF

echo "✅ Настройки Vercel сохранены в $BACKUP_DIR/vercel_config.md"

# 7. Создание скрипта восстановления
cat > "$BACKUP_DIR/restore.sh" << 'EOF'
#!/bin/bash
set -e

echo "🔄 Начинаем восстановление Restodocks..."

# 1. Восстановление кода
echo "📦 Восстанавливаем код..."
git clone https://github.com/stasssercheff/restodocks.git restored_project
cd restored_project

# 2. Восстановление переменных окружения
cp ../environment.env .env

# 3. Установка зависимостей
echo "📦 Устанавливаем зависимости..."
flutter pub get
npm install

# 4. Восстановление базы данных
echo "🗄️ Для восстановления базы данных выполните:"
echo "psql 'postgresql://postgres:[PASSWORD]@db.osglfptwbuqqmqunttha.supabase.co:5432/postgres' < ../database.sql"

# 5. Восстановление storage
echo "💾 Для восстановления storage используйте Supabase CLI"

echo "✅ Восстановление завершено. Проверьте настройки Vercel и Supabase."
EOF

chmod +x "$BACKUP_DIR/restore.sh"

# 8. Создание архива (пропуск при вызове из backup_all — там свой финальный архив)
if [ -z "$BACKUP_TARGET_DIR" ]; then
  echo "📦 Создание архива..."
  tar -czf "${BACKUP_DIR}.tar.gz" "$BACKUP_DIR"
  echo "✅ Архив создан: ${BACKUP_DIR}.tar.gz"
fi

# 9. Инструкции по ручному бэкапу
cat > "$BACKUP_DIR/MANUAL_BACKUP_README.md" << 'EOF'
# РУЧНОЙ БЭКАП - ДОПОЛНИТЕЛЬНЫЕ ШАГИ

## 1. База данных Supabase
```bash
# Установите Supabase CLI
npm install -g @supabase/cli
supabase login

# Или используйте pg_dump напрямую
pg_dump 'postgresql://postgres:[YOUR-PASSWORD]@db.osglfptwbuqqmqunttha.supabase.co:5432/postgres' > database_backup.sql
```

## 2. Supabase Storage
```bash
# Скачайте все файлы из бакетов
supabase storage download --project-ref osglfptwbuqqmqunttha [bucket-name] ./storage_backup/
```

## 3. Supabase Edge Functions
```bash
# Скачайте функции
supabase functions download --project-ref osglfptwbuqqmqunttha
```

## 4. Настройки аутентификации
- Проверьте SMTP настройки в Supabase Dashboard > Authentication > Email Templates
- Скачайте настройки RLS политик

## 5. Проверка бэкапа
- Протестируйте восстановление на staging окружении
- Проверьте целостность данных
EOF

echo ""
echo "🎉 БЭКАП ЗАВЕРШЕН!"
echo "📂 Директория: $BACKUP_DIR"
echo "📦 Архив: ${BACKUP_DIR}.tar.gz"
echo ""
echo "📋 Следующие шаги:"
echo "1. Выполните ручной бэкап базы данных (см. MANUAL_BACKUP_README.md)"
echo "2. Скачайте файлы из Supabase Storage"
echo "3. Протестируйте восстановление"
echo "4. Храните бэкап в надежном месте"