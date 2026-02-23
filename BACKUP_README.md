# Полный бэкап проекта Restodocks

Этот гайд поможет вам создать полный бэкап вашего сайта Restodocks, включая код, базу данных Supabase, файлы и конфигурацию.

## 📋 Что входит в полный бэкап

- ✅ **Код приложения** (GitHub репозиторий)
- ✅ **База данных** (Supabase PostgreSQL)
- ✅ **Файловое хранилище** (Supabase Storage)
- ✅ **Edge Functions** (Supabase Functions)
- ✅ **Конфигурация** (переменные окружения, настройки)
- ✅ **Настройки развертывания** (Vercel)

## 🚀 Быстрый старт

### 1. Одноразовый полный бэкап
```bash
./full_backup.sh
```

### 2. Автоматизированный бэкап
```bash
# Настройте конфигурацию
cp backup_config.env backup_config.env.local
# Отредактируйте backup_config.env.local с вашими данными

# Запустите автоматизированный бэкап
./automated_backup.sh
```

## 📚 Детальные инструкции

### Шаг 1: Настройка доступа к Supabase

#### Получение пароля базы данных:
1. Зайдите в [Supabase Dashboard](https://app.supabase.com)
2. Выберите проект `osglfptwbuqqmqunttha`
3. Перейдите: **Settings** → **Database**
4. Скопируйте **Connection string** или **Password**

#### Получение Service Role Key:
1. В Supabase Dashboard: **Settings** → **API**
2. Скопируйте **service_role** ключ (для полного доступа)

### Шаг 2: Ручной бэкап базы данных

```bash
# Вариант 1: через pg_dump
pg_dump 'postgresql://postgres:ВАШ_ПАРОЛЬ@db.osglfptwbuqqmqunttha.supabase.co:5432/postgres' > database_backup.sql

# Вариант 2: через Supabase CLI
supabase db dump --db-url 'postgresql://postgres:ВАШ_ПАРОЛЬ@db.osglfptwbuqqmqunttha.supabase.co:5432/postgres' > database_backup.sql

# Сжатие файла
gzip database_backup.sql
```

### Шаг 3: Бэкап Supabase Storage

```bash
# Установка Supabase CLI
npm install -g @supabase/cli
supabase login

# Просмотр доступных бакетов
supabase storage ls --project-ref osglfptwbuqqmqunttha

# Скачивание всех файлов
supabase storage download --project-ref osglfptwbuqqmqunttha bucket-name ./storage_backup/
```

### Шаг 4: Бэкап Edge Functions

```bash
# Скачивание функций
supabase functions download --project-ref osglfptwbuqqmqunttha
```

## ⏰ Автоматизация бэкапов

### Настройка cron для ежедневных бэкапов

```bash
# Редактируем crontab
crontab -e

# Добавляем строку для ежедневного бэкапа в 2:00 ночи
0 2 * * * cd /path/to/restodocks && ./automated_backup.sh

# Добавляем строку для еженедельного полного бэкапа по воскресеньям в 3:00
0 3 * * 0 cd /path/to/restodocks && ./full_backup.sh
```

### Docker-based бэкап

```bash
# Настройте переменные окружения
cp backup_config.env .env

# Запустите бэкап через Docker
docker-compose -f docker-compose.backup.yml up
```

## 🔄 Восстановление из бэкапа

### 1. Восстановление кода
```bash
git clone https://github.com/stasssercheff/restodocks.git restored_project
cd restored_project
cp ../backup/environment.env .env
flutter pub get
```

### 2. Восстановление базы данных
```bash
# Создайте новую базу данных или очистите существующую
psql 'postgresql://postgres:НОВЫЙ_ПАРОЛЬ@db.osglfptwbuqqmqunttha.supabase.co:5432/postgres' < database_backup.sql
```

### 3. Восстановление Storage
```bash
# Через Supabase CLI
supabase storage upload --project-ref osglfptwbuqqmqunttha bucket-name ./storage_backup/
```

### 4. Восстановление функций
```bash
supabase functions deploy --project-ref osglfptwbuqqmqunttha function-name
```

## 📊 Мониторинг и проверки

### Проверка целостности бэкапа
```bash
# Проверка размера файлов
ls -lah backup_*/database.sql.gz
ls -lah backup_*/storage_backup.tar.gz

# Проверка SQL файла
gunzip -c database_backup.sql.gz | head -20

# Проверка структуры storage
tar -tzf storage_backup.tar.gz | head -10
```

### Очистка старых бэкапов
```bash
# Оставить только последние 30 дней
find /backups -name "*.tar.gz" -mtime +30 -delete

# Оставить только последние 10 бэкапов
ls -t /backups/*.tar.gz | tail -n +11 | xargs rm -f
```

## 🔒 Безопасность

- **Храните бэкапы в нескольких местах**: локально + облако (AWS S3, Google Drive, etc.)
- **Шифруйте чувствительные данные**: используйте `gpg` для файлов с паролями
- **Ограничьте доступ**: храните бэкапы в защищенных директориях
- **Тестируйте восстановление**: регулярно проверяйте возможность восстановления

## 🆘 Устранение проблем

### Ошибка подключения к базе данных
```
# Проверьте пароль в Supabase Dashboard
# Убедитесь, что включен доступ из вашего IP
# Проверьте connection string
```

### Ошибка доступа к Storage
```
# Используйте service_role key вместо anon key
# Проверьте права доступа к бакетам
```

### Проблемы с Supabase CLI
```bash
# Переустановите CLI
npm uninstall -g @supabase/cli
npm install -g @supabase/cli

# Проверьте версию
supabase --version
```

## 📞 Поддержка

Если возникли проблемы:
1. Проверьте логи выполнения скриптов
2. Убедитесь, что все переменные окружения установлены
3. Проверьте доступ к Supabase Dashboard
4. Создайте issue в GitHub репозитории

## 📋 Чек-лист бэкапа

- [ ] Код скачан из GitHub
- [ ] База данных экспортирована
- [ ] Storage файлы скачаны
- [ ] Edge Functions сохранены
- [ ] Переменные окружения сохранены
- [ ] Настройки Vercel задокументированы
- [ ] Бэкап протестирован на восстановление
- [ ] Бэкап загружен в надежное хранилище