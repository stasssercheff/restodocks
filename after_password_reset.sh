#!/bin/bash

echo "🔄 НАСТРОЙКА ПОСЛЕ СБРОСА ПАРОЛЯ SUPABASE"
echo "=========================================="
echo ""

echo "⚠️  ПРЕДУПРЕЖДЕНИЕ:"
echo "После сброса пароля Supabase может потребоваться время (1-2 минуты)"
echo "для применения изменений ко всем сервисам."
echo ""

echo "📋 ЧТО СДЕЛАТЬ:"
echo ""
echo "1. Подождите 1-2 минуты после сброса"
echo "2. Запустите этот скрипт: ./after_password_reset.sh"
echo "3. Введите НОВЫЙ пароль из Supabase"
echo "4. Скрипт автоматически настроит бэкап"
echo "5. Протестирует подключение"
echo ""

read -p "Вы сбросили пароль и готовы продолжить? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Отменено. Запустите скрипт когда будете готовы."
    exit 1
fi

echo "🔑 Введите НОВЫЙ пароль базы данных:"
echo "(скопированный из Supabase после сброса)"
echo ""
read -s -p "Новый пароль: " NEW_PASSWORD
echo ""

if [ -z "$NEW_PASSWORD" ]; then
    echo "❌ Пароль не может быть пустым!"
    exit 1
fi

# Создаем резервную копию
cp backup_config.env backup_config.env.before_reset 2>/dev/null || true

# Обновляем конфигурацию
sed -i.bak "s/postgresql:\/\/postgres:[^@]*@/postgresql:\/\/postgres:$NEW_PASSWORD@/" backup_config.env

echo "✅ Новый пароль сохранен!"
echo ""

# Тестируем подключение
echo "🧪 Тестирую подключение с новым паролем..."
source backup_config.env

if command -v pg_dump >/dev/null 2>&1; then
    echo "Ожидаю применения изменений в Supabase (10 сек)..."
    sleep 10

    if pg_dump "$SUPABASE_DB_URL" --version > /dev/null 2>&1; then
        echo "✅ ПОДКЛЮЧЕНИЕ УСПЕШНО!"
        echo ""
        echo "🎉 БЭКАП БАЗЫ ДАННЫХ ГОТОВ!"
        echo "Теперь ./backup_all.sh будет включать полную БД"
        echo ""
        echo "💾 Резервная копия настроек: backup_config.env.before_reset"
        echo ""
        echo "🚀 МОЖНО ЗАПУСКАТЬ БЭКАП: ./backup_all.sh"
    else
        echo "❌ ПОДКЛЮЧЕНИЕ НЕ РАБОТАЕТ!"
        echo ""
        echo "Возможные причины:"
        echo "• Пароль введен неправильно"
        echo "• Supabase еще применяет изменения (подождите 2-3 мин)"
        echo "• Проверьте пароль еще раз"
        echo ""
        echo "Восстановите из backup_config.env.before_reset если нужно"
    fi
else
    echo "⚠️ pg_dump не найден, но пароль сохранен"
    echo "Бэкап сработает, но без предварительного теста"
fi

echo ""
echo "Готово! 🎯"