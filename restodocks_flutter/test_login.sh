#!/bin/bash
# Проверка Edge Function authenticate-employee
# Замени EMAIL и PASSWORD ниже на свои данные, потом запусти скрипт

EMAIL="ваш_email@example.com"
PASSWORD="ваш_пароль"

ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE"

echo "Проверяю вход..."
RESP=$(curl -s -w "\n%{http_code}" -X POST "https://osglfptwbuqqmqunttha.supabase.co/functions/v1/authenticate-employee" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ANON_KEY" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

HTTP_CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

echo "Ответ: $BODY"
echo "HTTP: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
  echo "OK — вход работает!"
else
  echo "401 — неверный email или пароль (или сотрудник не найден в БД)"
fi
