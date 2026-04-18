#!/usr/bin/env bash
# Синк RU-зеркала в Yandex Object Storage только после того, как прод restodocks.com
# уже выкатил ту же сборку, что в restodocks_flutter/pubspec.yaml (чтобы не заливать старый билд).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBSPEC="${ROOT}/restodocks_flutter/pubspec.yaml"
SRC_HOST="${SRC_HOST:-https://restodocks.com}"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found"
[[ -f "${PUBSPEC}" ]] || die "missing ${PUBSPEC}"

EXPECTED_BUILD="$(grep -E '^version:' "${PUBSPEC}" | sed -E 's/.*\+([0-9]+).*/\1/')"
[[ -n "${EXPECTED_BUILD}" ]] || die "could not parse build number from pubspec"

COM_JSON="$(curl -fsSL "${SRC_HOST}/version.json")"
COM_BUILD="$(printf '%s' "${COM_JSON}" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("build_number",""))')"

if [[ "${COM_BUILD}" != "${EXPECTED_BUILD}" ]]; then
  die "prod ${SRC_HOST}/version.json has build_number=${COM_BUILD}, pubspec expects +${EXPECTED_BUILD}. Wait for Cloudflare Pages (branch main) to finish, then retry."
fi

echo "OK: ${SRC_HOST} build ${COM_BUILD} matches pubspec (+${EXPECTED_BUILD}). Running Yandex sync..."
bash "${ROOT}/scripts/sync_ru_from_com.sh"

ENDPOINT_URL="${ENDPOINT_URL:-https://storage.yandexcloud.net}"
BUCKETS=("restodocks-ru-site" "www.restodocks.ru")

if command -v aws >/dev/null 2>&1; then
  for bucket in "${BUCKETS[@]}"; do
    RU_JSON="$(aws s3 cp "s3://${bucket}/version.json" - --endpoint-url "${ENDPOINT_URL}" 2>/dev/null)" || die "cannot read s3://${bucket}/version.json (aws CLI / credentials?)"
    RU_BUILD="$(printf '%s' "${RU_JSON}" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("build_number",""))')"
    if [[ "${RU_BUILD}" != "${EXPECTED_BUILD}" ]]; then
      die "after sync, s3://${bucket}/version.json has build_number=${RU_BUILD}, expected ${EXPECTED_BUILD}"
    fi
    echo "OK: s3://${bucket}/version.json -> build ${RU_BUILD}"
  done
else
  echo "WARN: aws CLI not found; skipping S3 readback check." >&2
fi

for url in "https://restodocks.ru/version.json" "https://www.restodocks.ru/version.json"; do
  if RU_JSON="$(curl -fsSL --connect-timeout 8 "${url}" 2>/dev/null)"; then
    RU_BUILD="$(printf '%s' "${RU_JSON}" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("build_number",""))')"
    if [[ "${RU_BUILD}" != "${EXPECTED_BUILD}" ]]; then
      die "HTTP ${url} has build_number=${RU_BUILD}, expected ${EXPECTED_BUILD}"
    fi
    echo "OK: ${url} -> build ${RU_BUILD}"
  else
    echo "SKIP: ${url} (no public DNS from this network — S3 check above is authoritative)" >&2
  fi
done

echo "All checks passed (prod +${EXPECTED_BUILD} = Yandex buckets; optional HTTP RU)."
