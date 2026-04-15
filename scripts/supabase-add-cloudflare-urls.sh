#!/usr/bin/env bash
# Патчит Supabase Auth config:
# 1) добавляет/сохраняет Redirect URLs для prod/beta/pages/local
# 2) включает Send Email Hook на Edge auth-send-email (если передан секрет)
#
# Требует:
#   SUPABASE_ACCESS_TOKEN
#   SUPABASE_PROJECT_REF
# Опционально:
#   SUPABASE_SEND_EMAIL_HOOK_SECRET (v1,whsec_...) — если задан, синхронизирует hook_send_email_*

set -euo pipefail

TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
REF="${SUPABASE_PROJECT_REF:-}"
HOOK_SECRET="${SUPABASE_SEND_EMAIL_HOOK_SECRET:-}"
API="https://api.supabase.com/v1"

if [ -z "$TOKEN" ] || [ -z "$REF" ]; then
  echo "Usage: SUPABASE_ACCESS_TOKEN=xxx SUPABASE_PROJECT_REF=xxx $0"
  exit 1
fi

HOOK_URL="https://${REF}.supabase.co/functions/v1/auth-send-email"

required_urls=(
  "https://restodocks.com"
  "https://restodocks.com/**"
  "https://www.restodocks.com"
  "https://www.restodocks.com/**"
  "https://restodocks.com/auth/confirm"
  "https://restodocks.com/auth/confirm-click"
  "https://www.restodocks.com/auth/confirm"
  "https://www.restodocks.com/auth/confirm-click"
  "https://*.restodocks.com/auth/confirm"
  "https://*.restodocks.com/auth/confirm-click"
  "https://*.restodocks.ru/auth/confirm"
  "https://*.restodocks.ru/auth/confirm-click"
  "https://restodocks.pages.dev"
  "https://restodocks.pages.dev/**"
  "https://restodocks.pages.dev/auth/confirm"
  "https://restodocks.pages.dev/auth/confirm-click"
  "https://*.restodocks.pages.dev/auth/confirm"
  "https://*.restodocks.pages.dev/auth/confirm-click"
  "https://*.pages.dev"
  "https://*.pages.dev/**"
  "https://demo.restodocks.com"
  "https://demo.restodocks.com/**"
  "https://demo.restodocks.com/auth/confirm"
  "https://demo.restodocks.com/auth/confirm-click"
  "http://localhost:3000"
  "http://localhost:8080"
  "http://127.0.0.1:3000"
  "http://127.0.0.1:8080"
)

echo "==> Fetching current auth config..."
CURRENT_JSON="$(curl -fsS \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${API}/projects/${REF}/config/auth")"

CURRENT_URLS="$(printf '%s' "${CURRENT_JSON}" | jq -c '.additional_redirect_urls // []')"
REQUIRED_URLS_JSON="$(printf '%s\n' "${required_urls[@]}" | jq -R . | jq -s .)"
MERGED_URLS="$(jq -cn --argjson a "${CURRENT_URLS}" --argjson b "${REQUIRED_URLS_JSON}" '$a + $b | unique')"
MERGED_URLS_CSV="$(printf '%s' "${MERGED_URLS}" | jq -r 'join(",")')"

if [ -n "$HOOK_SECRET" ]; then
  PATCH_BODY="$(jq -cn \
    --argjson urls "${MERGED_URLS}" \
    --arg urls_csv "${MERGED_URLS_CSV}" \
    --arg hook_url "${HOOK_URL}" \
    --arg hook_secret "${HOOK_SECRET}" \
    '{
      additional_redirect_urls: $urls,
      uri_allow_list: $urls_csv,
      hook_send_email_enabled: true,
      hook_send_email_uri: $hook_url,
      hook_send_email_secrets: $hook_secret
    }')"
  echo "==> Patching redirect URLs + send_email hook..."
else
  PATCH_BODY="$(jq -cn \
    --argjson urls "${MERGED_URLS}" \
    --arg urls_csv "${MERGED_URLS_CSV}" \
    '{additional_redirect_urls: $urls, uri_allow_list: $urls_csv}')"
  echo "==> Patching redirect URLs only (hook secret not provided)..."
fi

RESP="$(curl -sS -w '\n%{http_code}' -X PATCH \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PATCH_BODY}" \
  "${API}/projects/${REF}/config/auth")"

HTTP_CODE="$(printf '%s\n' "${RESP}" | tail -n1)"
BODY_RESP="$(printf '%s\n' "${RESP}" | sed '$d')"

if [ "${HTTP_CODE}" != "200" ]; then
  echo "PATCH failed: HTTP ${HTTP_CODE}"
  echo "${BODY_RESP}"
  exit 1
fi

echo "OK: Auth config updated."

VERIFY_JSON="$(curl -fsS \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${API}/projects/${REF}/config/auth")"

printf '%s' "${VERIFY_JSON}" | jq '{hook_send_email_enabled, hook_send_email_uri, redirects_count: (.additional_redirect_urls|length), uri_allow_list}'
