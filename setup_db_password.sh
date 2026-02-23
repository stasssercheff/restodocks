#!/bin/bash

echo "🔐 НАСТРОЙКА ПАРОЛЯ БАЗЫ ДАННЫХ SUPABASE"
echo "=========================================="
echo ""

# Проверяем наличие файла конфигурации
if [ ! -f "backup_config.env" ]; then
    echo "❌ Файл backup_config.env не найден!"
    exit 1
fi

echo "📋 Текущая настройка:"
grep "SUPABASE_DB_URL" backup_config.env
echo ""

# Запрашиваем пароль у пользователя
echo "🔑 Введите пароль базы данных из Supabase Dashboard:"
echo "(Settings → Database → Database password)"
echo ""
read -s -p "Пароль: " DB_PASSWORD
echo ""

if [ -z "$DB_PASSWORD" ]; then
    echo "❌ Пароль не может быть пустым!"
    exit 1
fi

# Создаем резервную копию
cp backup_config.env backup_config.env.backup

# Обновляем конфигурацию
sed -i.bak "s/YOUR_DB_PASSWORD_HERE/$DB_PASSWORD/g" backup_config.env

echo "✅ Пароль сохранен в backup_config.env"
echo ""

# Тестируем подключение
echo "🧪 Тестирую подключение..."
source backup_config.env

if command -v pg_dump >/dev/null 2>&1; then
    if pg_dump "$SUPABASE_DB_URL" --version > /dev/null 2>&1; then
        echo "✅ ПОДКЛЮЧЕНИЕ УСПЕШНО!"
        echo ""
        echo "🎉 База данных готова для бэкапа!"
        echo "Теперь ./backup_all.sh будет автоматически бэкапить БД"
        echo ""
        echo "💡 Резервная копия: backup_config.env.backup"
    else
        echo "❌ ОШИБКА ПОДКЛЮЧЕНИЯ!"
        echo ""
        echo "Возможные причины:"
        echo "• Неправильный пароль"
        echo "• IP-адрес заблокирован"
        echo ""
        echo "Восстановите из backup_config.env.backup и попробуйте снова"
        mv backup_config.env.backup backup_config.env
    fi
else
    echo "⚠️ pg_dump не найден, но пароль сохранен"
    echo "Установите pg_dump для тестирования: brew install postgresql"
fi

echo ""
echo "Готово! 🚀"