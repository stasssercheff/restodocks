#!/usr/bin/env bash
# Поднять лимиты Supabase Auth (429 на signup / email) через Management API.
# Токен: https://supabase.com/dashboard/account/tokens
#
# Использование:
#   export SUPABASE_ACCESS_TOKEN="sbp_..."
#   ./scripts/raise-supabase-auth-rate-limits.sh
#
# Опционально: PROJECT_REF=osglfptwbuqqmqunttha (по умолчанию — Restodocks prod)

set -euo pipefail
PROJECT_REF="${PROJECT_REF:-osglfptwbuqqmqunttha}"
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "Задайте SUPABASE_ACCESS_TOKEN (Personal Access Token из Supabase Dashboard)." >&2
  exit 1
fi

# Значения выше дефолтных из доки (10) — для продакшена и тестов без многочасовой блокировки.
# Дополнительно: Dashboard → Authentication → Rate Limits (для signup_confirmation.period и т.д.).
BODY='{
  "rate_limit_anonymous_users": 60,
  "rate_limit_email_sent": 60,
  "rate_limit_sms_sent": 30,
  "rate_limit_verify": 60,
  "rate_limit_token_refresh": 180,
  "rate_limit_otp": 60,
  "rate_limit_web3": 30
}'

echo "PATCH https://api.supabase.com/v1/projects/${PROJECT_REF}/config/auth"
RESP=$(curl -sS -w "\n%{http_code}" -X PATCH \
  "https://api.supabase.com/v1/projects/${PROJECT_REF}/config/auth" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${BODY}")
CODE=$(echo "$RESP" | tail -n1)
BODY_OUT=$(echo "$RESP" | sed '$d')
if [[ "$CODE" =~ ^2 ]]; then
  echo "OK (HTTP $CODE)"
  echo "$BODY_OUT" | head -c 500
  echo
else
  echo "Ошибка HTTP $CODE" >&2
  echo "$BODY_OUT" >&2
  exit 1
fi
