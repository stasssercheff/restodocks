# Программа информационной безопасности Restodocks

Цель: защита данных клиентов и устойчивость сервиса в духе общепринятых практик (OWASP ASVS, принципы NIST, подготовка к ISO 27001 / SOC 2).  
Сертификация требует отдельного аудита организации; этот документ описывает **технические** и **операционные** меры в репозитории.

## 1. Модель угроз (кратко)

- Публичный **anon key** в клиенте — норма для Supabase; защита = **RLS + RPC + Edge Functions**, не секретность ключа.
- **Service role** обходит RLS — только сервер (Edge Functions, CI), никогда в браузере/приложении.
- Основные риски: обход tenant (IDOR), спам через API, утечка секретов, слабые политики `anon`.

## 2. Реализовано в коде и миграциях

| Область | Мера |
|--------|------|
| PostgreSQL | RLS на таблицах с данными; политики с `current_user_establishment_ids()` где нужен tenant |
| Регистрация | Создание заведений через `register_company_with_promo` и RPC, не прямой anon INSERT |
| Edge `send-email` | Лимиты по IP и пользователю, размеры тел, путь service role vs JWT |
| `product_alias_rejections`, `product_aliases`, nutrition, iiko blanks, ai_ttk, tt_parse | См. миграции `20260429140000`, `20260429160000` |
| POS / склад / `system_errors` / `tech_card_change_requests` | См. `20260430100000` (anon снят, tenant через `current_user_establishment_ids()`; опасные policy на `employees` / `allow_all_establishment_products` — drop при наличии) |
| Секреты | Service role в Supabase Secrets; `backup_config.env` в `.gitignore` |

## 3. Операционный чек-лист (регулярно)

Пошагово для владельца без отдельной роли security: **`docs/SECURITY_OWNER_CHECKLIST.md`**.

1. **Миграции** на Beta/Prod совпадают с `supabase/migrations` (после merge — `supabase db push` или ручной SQL).
2. **Edge Functions** задеплоены после изменений в `restodocks_flutter/supabase/functions`.
3. **Ключи**: ротация при утечке; MFA на GitHub и Supabase Dashboard для админов.
4. **Бэкапы** Supabase (план проекта) и проверка восстановления.
5. **Cloudflare**: WAF, rate limiting, список разрешённых origin для чувствительных зон.
6. **Сканирование**: Dependabot / `dart pub outdated` / аудит npm в admin.

## 4. Аудит RLS вручную

```bash
# В репозитории:
# Выполнить scripts/security_audit_rls.sql в SQL Editor и проверить политики для role anon.
```

## 5. Дорожная карта (следующие усиления)

- Периодический **пентест** или OWASP ZAP против staging.
- Централизованные **логи** и алерты (ошибки 401/429, всплески RPC).
- Политики **ретенции** и удаления персональных данных (GDPR-запросы).

## 6. Ответственность

Владелец продукта подтверждает применение миграций и секретов на проектах Supabase; код задаёт намерение, прод-конфигурация должна ему соответствовать.
