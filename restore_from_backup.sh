#!/bin/bash
set -e

# Скрипт восстановления из бэкапа Restodocks

echo "🔄 ВОССТАНОВЛЕНИЕ ИЗ БЭКАПА RESTODOCKS"
echo "========================================"

# Проверяем аргументы
if [ $# -eq 0 ]; then
    echo "❌ Укажите архив бэкапа!"
    echo ""
    echo "📋 ДОСТУПНЫЕ АРХИВЫ:"
    ls -lh *COMPLETE.tar.gz 2>/dev/null || echo "Архивы не найдены"
    echo ""
    echo "💡 ИСПОЛЬЗОВАНИЕ:"
    echo "   ./restore_from_backup.sh backup_20260222_151114_COMPLETE.tar.gz"
    echo "   или"
    echo "   ./restore_from_backup.sh  # покажет список архивов"
    exit 1
fi

BACKUP_ARCHIVE="$1"

if [ ! -f "$BACKUP_ARCHIVE" ]; then
    echo "❌ Архив '$BACKUP_ARCHIVE' не найден!"
    exit 1
fi

echo "📦 АРХИВ: $BACKUP_ARCHIVE"
echo "📊 РАЗМЕР: $(ls -lh "$BACKUP_ARCHIVE" | awk '{print $5}')"
echo ""

# Создаем директорию для восстановления
RESTORE_DIR="restored_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESTORE_DIR"

echo "📁 СОЗДАЮ ДИРЕКТОРИЮ ВОССТАНОВЛЕНИЯ: $RESTORE_DIR"
echo ""

# 1. Распаковка архива
echo "📦 ШАГ 1: Распаковка архива..."
tar -xzf "$BACKUP_ARCHIVE" -C "$RESTORE_DIR"

# Определяем имя распакованной папки
EXTRACTED_DIR=$(find "$RESTORE_DIR" -maxdepth 1 -type d | tail -1)
echo "   ✅ Архив распакован в: $EXTRACTED_DIR"
echo ""

# 2. Восстановление кода
echo "📦 ШАГ 2: Восстановление кода..."
if [ -d "$EXTRACTED_DIR/code" ]; then
    echo "   Копируем код проекта..."
    cp -r "$EXTRACTED_DIR/code"/* ./
    echo "   ✅ Код восстановлен"
else
    echo "   ⚠️ Папка code не найдена в архиве"
fi

# 3. Восстановление конфигурации
echo ""
echo "⚙️ ШАГ 3: Восстановление конфигурации..."
if [ -f "$EXTRACTED_DIR/environment.env" ]; then
    cp "$EXTRACTED_DIR/environment.env" .env
    echo "   ✅ Переменные окружения восстановлены (.env)"
fi

if [ -d "$EXTRACTED_DIR/supabase_config" ]; then
    mkdir -p supabase/migrations
    mkdir -p supabase/functions
    cp -r "$EXTRACTED_DIR/supabase_config/migrations/"* supabase/migrations/ 2>/dev/null || true
    cp -r "$EXTRACTED_DIR/supabase_config/functions/"* supabase/functions/ 2>/dev/null || true
    cp "$EXTRACTED_DIR/supabase_config/"*.sql . 2>/dev/null || true
    echo "   ✅ Supabase конфигурация восстановлена"
fi

# 4. Проверка зависимостей
echo ""
echo "📦 ШАГ 4: Проверка зависимостей..."
if [ -f "pubspec.yaml" ]; then
    echo "   Flutter проект найден"
    echo "   Запустите: flutter pub get"
fi

if [ -f "package.json" ]; then
    echo "   Node.js проект найден"
    echo "   Запустите: npm install"
fi

# 5. Инструкции по восстановлению базы данных
echo ""
echo "🗄️ ШАГ 5: ВОССТАНОВЛЕНИЕ БАЗЫ ДАННЫХ"
echo "====================================="

if [ -f "$EXTRACTED_DIR/database.sql.gz" ]; then
    echo "✅ ДАМП БАЗЫ ДАННЫХ НАЙДЕН!"
    echo ""
    echo "📋 ИНСТРУКЦИИ:"
    echo "1. Распакуйте дамп: gunzip database.sql.gz"
    echo "2. Создайте новую базу данных в Supabase"
    echo "3. Восстановите данные:"
    echo "   psql 'postgresql://postgres:[ПАРОЛЬ]@db.osglfptwbuqqmqunttha.supabase.co:5432/postgres' < database.sql"
    echo ""
    echo "⚠️  ВАЖНО: Используйте новый пароль базы данных!"
else
    echo "⚠️ ДАМП БАЗЫ ДАННЫХ НЕ НАЙДЕН В АРХИВЕ"
    echo "   Возможно, pg_dump не был настроен во время бэкапа"
    echo ""
    echo "📋 ВОССТАНОВЛЕНИЕ СУЩЕСТВУЮЩЕЙ БД:"
    echo "1. Зайдите в Supabase Dashboard"
    echo "2. Database → Settings → Database password"
    echo "3. Сбросьте пароль если нужно"
    echo "4. Примените миграции: supabase db push"
fi

# 6. Инструкции по восстановлению storage
echo ""
echo "💾 ШАГ 6: ВОССТАНОВЛЕНИЕ STORAGE"
echo "==============================="

if [ -d "$EXTRACTED_DIR/storage_backup" ] && [ "$(ls -A "$EXTRACTED_DIR/storage_backup" 2>/dev/null)" ]; then
    echo "✅ ФАЙЛЫ STORAGE НАЙДЕНЫ!"
    echo ""
    echo "📋 ИНСТРУКЦИИ:"
    echo "1. Установите Supabase CLI: npm install -g @supabase/cli"
    echo "2. Авторизуйтесь: supabase login"
    echo "3. Загрузите файлы:"
    echo "   supabase storage upload [bucket-name] ./$EXTRACTED_DIR/storage_backup/ --project-ref osglfptwbuqqmqunttha"
else
    echo "⚠️ ФАЙЛЫ STORAGE НЕ НАЙДЕНЫ"
    echo "   Возможно, storage был пустой или не настроен"
fi

# 7. Финальные инструкции
echo ""
echo "🚀 ШАГ 7: ЗАВЕРШЕНИЕ ВОССТАНОВЛЕНИЯ"
echo "==================================="

echo "✅ ВОССТАНОВЛЕНИЕ ЗАВЕРШЕНО!"
echo ""
echo "📁 ДИРЕКТОРИЯ ВОССТАНОВЛЕНИЯ: $RESTORE_DIR"
echo "📦 АРХИВ: $BACKUP_ARCHIVE"
echo ""
echo "🎯 ДАЛЬНЕЙШИЕ ШАГИ:"
echo "1. Проверьте что код восстановлен: ls -la"
echo "2. Установите зависимости: flutter pub get && npm install"
echo "3. Восстановите базу данных (см. ШАГ 5)"
echo "4. Восстановите storage (см. ШАГ 6)"
echo "5. Разверните проект: flutter build web"
echo "6. Настройте Vercel с переменными из .env"
echo ""
echo "💡 ЕСЛИ ЧТО-ТО ПОШЛО НЕ ТАК:"
echo "   Удалите $RESTORE_DIR и попробуйте снова"
echo "   Или восстановите из другого архива"
echo ""
echo "🎉 ГОТОВО! Проект восстановлен из бэкапа."