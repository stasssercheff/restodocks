#!/usr/bin/env bash
# Watchdog: проверка всплесков 401/429/5xx на публичной цепочке регистрации.
# Не проверяет бизнес-данные, только стабильность доступности и авторизации Edge-эндпоинтов.

set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:-https://osglfptwbuqqmqunttha.supabase.co}"
SAMPLES="${SAMPLES:-6}"
SLEEP_SECONDS="${SLEEP_SECONDS:-2}"
MAX_429="${MAX_429:-1}"
MAX_5XX="${MAX_5XX:-1}"

if [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "Missing SUPABASE_ANON_KEY" >&2
  exit 1
fi

BASE="${SUPABASE_URL%/}"
HDR=(
  -H "apikey: ${SUPABASE_ANON_KEY}"
  -H "Authorization: Bearer ${SUPABASE_ANON_KEY}"
  -H "Content-Type: application/json"
)

count_401=0
count_429=0
count_5xx=0

request_code() {
  local url="$1"
  local body="$2"
  curl -sS -o /tmp/rd_watchdog_resp.json -w "%{http_code}" -X POST "${url}" "${HDR[@]}" -d "${body}" || echo "599"
}

echo "Running ${SAMPLES} samples for edge status watchdog..."

for ((i = 1; i <= SAMPLES; i++)); do
  meta_code="$(request_code "${BASE}/functions/v1/register-metadata" '{"establishment_id":"00000000-0000-4000-8000-000000000001"}')"
  mail_code="$(request_code "${BASE}/functions/v1/send-registration-email" '{"type":"confirmation_only","to":"watchdog-anon-check@invalid.restodocks","language":"en"}')"

  for code in "${meta_code}" "${mail_code}"; do
    if [[ "${code}" == "401" ]]; then
      ((count_401 += 1))
    fi
    if [[ "${code}" == "429" ]]; then
      ((count_429 += 1))
    fi
    if [[ "${code}" =~ ^5[0-9][0-9]$ ]] || [[ "${code}" == "599" ]]; then
      ((count_5xx += 1))
    fi
  done

  echo "Sample ${i}/${SAMPLES}: register-metadata=${meta_code}, send-registration-email=${mail_code}"
  if [[ "${i}" -lt "${SAMPLES}" ]]; then
    sleep "${SLEEP_SECONDS}"
  fi
done

echo "Summary: 401=${count_401}, 429=${count_429}, 5xx=${count_5xx}"

if [[ "${count_401}" -gt 0 ]]; then
  echo "WATCHDOG FAIL: detected 401 responses in anon registration chain" >&2
  exit 1
fi

if [[ "${count_429}" -gt "${MAX_429}" ]]; then
  echo "WATCHDOG FAIL: 429 spike detected (${count_429} > ${MAX_429})" >&2
  exit 1
fi

if [[ "${count_5xx}" -gt "${MAX_5XX}" ]]; then
  echo "WATCHDOG FAIL: 5xx spike detected (${count_5xx} > ${MAX_5XX})" >&2
  exit 1
fi

echo "WATCHDOG OK: no spike thresholds exceeded."
