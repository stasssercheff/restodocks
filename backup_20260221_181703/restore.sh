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
