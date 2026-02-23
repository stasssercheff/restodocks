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
