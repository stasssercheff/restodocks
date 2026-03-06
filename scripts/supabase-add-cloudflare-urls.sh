#!/usr/bin/env bash
# Добавляет Cloudflare Pages URL в Supabase Auth (Redirect URLs + Site URL).
# Требует: SUPABASE_ACCESS_TOKEN (из https://supabase.com/dashboard/account/tokens)
#           SUPABASE_PROJECT_REF (например kzhaezanjttvnqkgpxnh для Staging)
#
# Использование:
#   SUPABASE_ACCESS_TOKEN=sbp_xxx SUPABASE_PROJECT_REF=kzhaezanjttvnqkgpxnh ./scripts/supabase-add-cloudflare-urls.sh

set -e

TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
REF="${SUPABASE_PROJECT_REF:-}"
API="https://api.supabase.com/v1"

if [ -z "$TOKEN" ] || [ -z "$REF" ]; then
  echo "Usage: SUPABASE_ACCESS_TOKEN=xxx SUPABASE_PROJECT_REF=xxx $0"
  echo "  SUPABASE_ACCESS_TOKEN: Personal Access Token from https://supabase.com/dashboard/account/tokens"
  echo "  SUPABASE_PROJECT_REF: project ref from your Supabase URL (e.g. kzhaezanjttvnqkgpxnh)"
  exit 1
fi

# Cloudflare Pages URLs для prod + beta
CLOUDFLARE_URLS=(
  "https://restodocks.pages.dev"
  "https://restodocks.pages.dev/**"
  "https://*.pages.dev"
  "https://*.pages.dev/**"
)

# Собираем полный список (Cloudflare + localhost)
REDIRECT_JSON=$(printf '%s\n' "${CLOUDFLARE_URLS[@]}" \
  "http://localhost:3000" \
  "http://localhost:8080" \
  "http://127.0.0.1:3000" \
  "http://127.0.0.1:8080" \
  "https://restodocks.com" \
  "https://restodocks.com/**" \
  "https://www.restodocks.com" \
  "https://www.restodocks.com/**" \
  "https://demo.restodocks.com" \
  "https://demo.restodocks.com/**" \
  | jq -R . | jq -s .)

# PATCH с site_url и additional_redirect_urls
# Документация: https://supabase.com/docs/guides/auth/redirect-urls
BODY=$(jq -n \
  --arg site "https://restodocks.pages.dev" \
  --argjson urls "$REDIRECT_JSON" \
  '{site_url: $site, additional_redirect_urls: $urls}')

echo "==> Patching auth config (site_url + additional_redirect_urls)..."
RESP=$(curl -s -w "\n%{http_code}" -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY" \
  "$API/projects/$REF/config/auth")

HTTP_CODE=$(echo "$RESP" | tail -n1)
BODY_RESP=$(echo "$RESP" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
  echo "OK: Auth config updated. Cloudflare URLs added."
else
  echo "HTTP $HTTP_CODE: $BODY_RESP"
  echo ""
  echo "Если API не поддерживает additional_redirect_urls, добавьте вручную:"
  echo "  Supabase Dashboard -> Project -> Authentication -> URL Configuration"
  echo "  Redirect URLs:"
  printf '    %s\n' "${CLOUDFLARE_URLS[@]}"
  exit 1
fi
