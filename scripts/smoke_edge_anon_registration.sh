#!/usr/bin/env bash
# Смок: Edge Functions с тем же anon, что и клиент (postEdgeFunctionWithRetry: apikey + Bearer anon).
# Цель — не словить снова 401 из-за несогласованной авторизации (register-metadata / send-registration-email).
#
# Запуск (из корня репозитория; anon — из Supabase Dashboard → Settings → API, тот же что в сборке web):
#   export SUPABASE_ANON_KEY='eyJ...'
#   ./scripts/smoke_edge_anon_registration.sh
#
# Опционально: SUPABASE_URL (по умолчанию osglfptwbuqqmqunttha).
#
# Успех: оба запроса НЕ возвращают 401. Допустимы 404 (нет заведения), 400 (нет пользователя для ссылки),
# 429 (лимит), 500 (нет RESEND и т.д.) — это уже не «сломана проверка anon».
# Провал: HTTP 401 = anon до функции не доходит или hasValidApiKeyOrUser отклоняет.

set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:-https://osglfptwbuqqmqunttha.supabase.co}"
if [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "Задайте SUPABASE_ANON_KEY (anon public из Dashboard — должен совпадать с ключом в вашей сборке Flutter/web)." >&2
  exit 1
fi

BASE="${SUPABASE_URL%/}"
HDR=(
  -H "apikey: ${SUPABASE_ANON_KEY}"
  -H "Authorization: Bearer ${SUPABASE_ANON_KEY}"
  -H "Content-Type: application/json"
)

fail() {
  echo "SMOKE FAIL: $*" >&2
  exit 1
}

echo "== register-metadata (ожидаем не 401; часто 404 если UUID не существует) =="
# Стабильный несуществующий UUID — проверяем только прохождение anon, не данные.
BODY_META='{"establishment_id":"00000000-0000-4000-8000-000000000001"}'
code=$(curl -sS -o /tmp/rd_smoke_register_metadata.json -w "%{http_code}" -X POST \
  "${BASE}/functions/v1/register-metadata" "${HDR[@]}" -d "${BODY_META}")
echo "HTTP ${code}"
cat /tmp/rd_smoke_register_metadata.json 2>/dev/null | head -c 400 || true
echo ""
if [[ "${code}" == "401" ]]; then
  fail "register-metadata вернул 401 — anon/JWT или verify_jwt на шлюзе"
fi

echo ""
echo "== send-registration-email confirmation_only (ожидаем не 401; часто 400/500 без реального пользователя/Resend) =="
BODY_MAIL='{"type":"confirmation_only","to":"smoke-anon-check@invalid.restodocks","language":"en"}'
code=$(curl -sS -o /tmp/rd_smoke_send_registration_email.json -w "%{http_code}" -X POST \
  "${BASE}/functions/v1/send-registration-email" "${HDR[@]}" -d "${BODY_MAIL}")
echo "HTTP ${code}"
cat /tmp/rd_smoke_send_registration_email.json 2>/dev/null | head -c 400 || true
echo ""
if [[ "${code}" == "401" ]]; then
  fail "send-registration-email вернул 401 — anon/JWT или verify_jwt на шлюзе"
fi

echo ""
echo "SMOKE OK: ни один из эндпоинтов не ответил 401 (anon-цепочка жива)."
