# Миграция на Supabase — инструкция

## Выполните SQL-миграции в Supabase Dashboard

1. Откройте [Supabase Dashboard](https://app.supabase.com) → ваш проект → **SQL Editor**

2. Выполните в таком порядке:

### 1. Политики для регистрации
Файл: `supabase_migration_auth_signup.sql`
- Разрешает создание establishment и employee при signUp

### 2. Таблица shifts и колонки employees
Файл: `supabase_migration_shifts.sql`
- Добавляет `cost_per_unit`, `payroll_counting_mode` в employees
- Создаёт таблицу `shifts` с RLS

## Проверка

После миграции:
- Регистрация компании и владельца
- Вход по email + пароль + PIN компании
- Создание сотрудников
- Создание смен
- Расчёт зарплаты

Все данные теперь хранятся только в Supabase.
