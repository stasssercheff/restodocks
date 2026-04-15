#!/usr/bin/env bash
set -euo pipefail

TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
REF="${SUPABASE_PROJECT_REF:-osglfptwbuqqmqunttha}"
HOOK_SECRET="${SUPABASE_SEND_EMAIL_HOOK_SECRET:-}"
API="https://api.supabase.com/v1"

if [ -z "$TOKEN" ] || [ -z "$HOOK_SECRET" ]; then
  echo "Missing required env vars: SUPABASE_ACCESS_TOKEN, SUPABASE_SEND_EMAIL_HOOK_SECRET"
  exit 1
fi

HOOK_URL="https://${REF}.supabase.co/functions/v1/auth-send-email"

required_urls=(
  "https://restodocks.com/auth/confirm"
  "https://restodocks.com/auth/confirm-click"
  "https://www.restodocks.com/auth/confirm"
  "https://www.restodocks.com/auth/confirm-click"
  "https://restodocks.pages.dev/auth/confirm"
  "https://restodocks.pages.dev/auth/confirm-click"
  "https://*.restodocks.pages.dev/auth/confirm"
  "https://*.restodocks.pages.dev/auth/confirm-click"
  "https://*.pages.dev"
  "https://*.pages.dev/**"
  "https://demo.restodocks.com/auth/confirm"
  "https://demo.restodocks.com/auth/confirm-click"
  "https://demo.restodocks.com/**"
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

PATCH_BODY="$(jq -cn \
  --argjson urls "${MERGED_URLS}" \
  --arg hook_url "${HOOK_URL}" \
  --arg hook_secret "${HOOK_SECRET}" \
  '{
    additional_redirect_urls: $urls,
    hook_send_email_enabled: true,
    hook_send_email_uri: $hook_url,
    hook_send_email_secrets: $hook_secret
  }')"

echo "==> Patching auth config (redirect URLs + send_email hook)..."
RESP="$(curl -sS -w '\n%{http_code}' -X PATCH \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${PATCH_BODY}" \
  "${API}/projects/${REF}/config/auth")"

HTTP_CODE="$(printf '%s\n' "${RESP}" | tail -n1)"
RESP_BODY="$(printf '%s\n' "${RESP}" | sed '$d')"

if [ "${HTTP_CODE}" != "200" ]; then
  echo "PATCH failed: HTTP ${HTTP_CODE}"
  echo "${RESP_BODY}"
  exit 1
fi

echo "OK: Auth config updated."
echo "==> Verifying send_email hook state..."
VERIFY_JSON="$(curl -fsS \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${API}/projects/${REF}/config/auth")"

printf '%s' "${VERIFY_JSON}" | jq '{hook_send_email_enabled, hook_send_email_uri, redirects_count: (.additional_redirect_urls|length)}'
