#!/bin/bash
set -e

echo "🧪 Тестирование компонентов бэкапа Restodocks"

# Проверяем наличие необходимых инструментов
echo "🔧 Проверка инструментов..."

command -v git >/dev/null 2>&1 && echo "✅ git найден" || echo "❌ git не найден"
command -v pg_dump >/dev/null 2>&1 && echo "✅ pg_dump найден" || echo "❌ pg_dump не найден"
command -v supabase >/dev/null 2>&1 && echo "✅ supabase CLI найден" || echo "❌ supabase CLI не найден (npm install -g @supabase/cli)"
command -v flutter >/dev/null 2>&1 && echo "✅ flutter найден" || echo "❌ flutter не найден"
command -v node >/dev/null 2>&1 && echo "✅ node найден" || echo "❌ node не найден"
command -v python3 >/dev/null 2>&1 && echo "✅ python3 найден" || echo "❌ python3 не найден"

# Проверяем конфигурационные файлы
echo ""
echo "📁 Проверка файлов конфигурации..."

[ -f ".env" ] && echo "✅ .env найден" || echo "❌ .env не найден"
[ -f "backup_config.env" ] && echo "✅ backup_config.env найден" || echo "❌ backup_config.env не найден"
[ -f "full_backup.sh" ] && echo "✅ full_backup.sh найден" || echo "❌ full_backup.sh не найден"
[ -f "automated_backup.sh" ] && echo "✅ automated_backup.sh найден" || echo "❌ automated_backup.sh не найден"

# Проверяем доступ к репозиторию
echo ""
echo "📦 Проверка доступа к GitHub..."
if git ls-remote https://github.com/stasssercheff/restodocks.git >/dev/null 2>&1; then
    echo "✅ Доступ к GitHub репозиторию есть"
else
    echo "❌ Нет доступа к GitHub репозиторию"
fi

# Проверяем переменные окружения
echo ""
echo "🔐 Проверка переменных окружения..."
[ -n "$SUPABASE_URL" ] && echo "✅ SUPABASE_URL установлена" || echo "❌ SUPABASE_URL не установлена"
[ -n "$SUPABASE_ANON_KEY" ] && echo "✅ SUPABASE_ANON_KEY установлена" || echo "❌ SUPABASE_ANON_KEY не установлена"

# Проверяем подключение к Supabase (если установлены ключи)
if [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_ANON_KEY" ]; then
    echo ""
    echo "🔗 Тест подключения к Supabase..."
    if command -v curl >/dev/null 2>&1; then
        response=$(curl -s -o /dev/null -w "%{http_code}" "$SUPABASE_URL/rest/v1/" -H "apikey: $SUPABASE_ANON_KEY")
        if [ "$response" = "200" ] || [ "$response" = "401" ]; then
            echo "✅ Подключение к Supabase работает (HTTP $response)"
        else
            echo "❌ Проблема с подключением к Supabase (HTTP $response)"
        fi
    fi
fi

# Проверяем Supabase CLI авторизацию
if command -v supabase >/dev/null 2>&1; then
    echo ""
    echo "🔑 Проверка авторизации Supabase CLI..."
    if supabase projects list >/dev/null 2>&1; then
        echo "✅ Supabase CLI авторизован"
    else
        echo "❌ Supabase CLI не авторизован (запустите: supabase login)"
    fi
fi

echo ""
echo "📋 Рекомендации:"
echo "- Установите все недостающие инструменты"
echo "- Настройте переменные окружения в backup_config.env"
echo "- Авторизуйтесь в Supabase CLI: supabase login"
echo "- Протестируйте подключение к базе данных вручную"
echo ""
echo "✅ Тестирование завершено"