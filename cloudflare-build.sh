#!/usr/bin/env bash
# Wrapper для Cloudflare Pages: сборка идёт из корня репо.
set -e
cd "$(dirname "$0")/restodocks_flutter" || exit 1
exec ./cloudflare-build.sh
