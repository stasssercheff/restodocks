#!/usr/bin/env bash
# Production: основной сайт — всегда Production Supabase.
set -e
cd "$(dirname "$0")/restodocks_flutter" || exit 1
exec ./cloudflare-build-prod.sh
