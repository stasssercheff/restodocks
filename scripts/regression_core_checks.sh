#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== 1) Translation regression =="
python3 scripts/check_translation_regression.py

echo ""
echo "== 2) Flutter core tests (registration/parsing/model) =="
cd restodocks_flutter
flutter test test/widget_test.dart
flutter test test/haccp_frying_oil_test.dart
flutter test test/parsing_smoke_test.dart
flutter test test/export_smoke_test.dart

echo ""
echo "== 3) Edge anon smoke (registration/email chain) =="
cd "$ROOT"
if [[ -n "${SUPABASE_ANON_KEY:-}" ]]; then
  ./scripts/smoke_edge_anon_registration.sh
else
  if [[ "${CI_REQUIRE_EDGE_SMOKE:-0}" == "1" ]]; then
    echo "FAIL: SUPABASE_ANON_KEY is required in CI but missing" >&2
    exit 1
  fi
  echo "SKIP: SUPABASE_ANON_KEY is not set (local mode)"
fi

echo ""
echo "REGRESSION CORE CHECKS: OK"
