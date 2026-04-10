#!/usr/bin/env bash
set -euo pipefail

# Sync restodocks.ru buckets from current restodocks.com build.
# Requires:
#   - aws CLI configured with Yandex Object Storage credentials
#   - access to buckets: restodocks-ru-site, www.restodocks.ru
#
# Usage:
#   bash scripts/sync_ru_from_com.sh

ENDPOINT_URL="${ENDPOINT_URL:-https://storage.yandexcloud.net}"
SRC_HOST="${SRC_HOST:-https://restodocks.com}"
TMP_DIR="${TMP_DIR:-/tmp/restodocks_com_mirror}"
META_DIR="${META_DIR:-/tmp/restodocks_com_meta}"
BUCKETS=("restodocks-ru-site" "www.restodocks.ru")

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }

command -v aws >/dev/null 2>&1 || {
  echo "ERROR: aws CLI not found. Install AWS CLI first."
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 not found."
  exit 1
}
command -v curl >/dev/null 2>&1 || {
  echo "ERROR: curl not found."
  exit 1
}

mkdir -p "$TMP_DIR"
mkdir -p "$META_DIR"
rm -rf "$TMP_DIR"/*
rm -rf "$META_DIR"/*

log "Checking source version from ${SRC_HOST}/version.json"
curl -fsSL "${SRC_HOST}/version.json" | tee "${META_DIR}/version_from_com.json"

log "Building keys list from reference bucket ${BUCKETS[0]}"
aws s3 ls "s3://${BUCKETS[0]}" --recursive --endpoint-url "$ENDPOINT_URL" \
  | awk '{ $1=$2=$3=""; sub(/^   /,""); print }' \
  | sed '/^$/d' > "${META_DIR}/keys.txt"

log "Downloading current prod files from ${SRC_HOST}"
python3 - <<'PY'
import pathlib, subprocess, sys
from urllib.parse import quote

tmp = pathlib.Path("/tmp/restodocks_com_mirror")
keys = pathlib.Path("/tmp/restodocks_com_meta/keys.txt").read_text(encoding="utf-8").splitlines()
src = "https://restodocks.com"
ok = 0
for key in keys:
    dest = tmp / key
    if dest.parent.exists() and dest.parent.is_file():
        dest.parent.unlink()
    dest.parent.mkdir(parents=True, exist_ok=True)
    url = src + "/" + quote(key)
    r = subprocess.run(["curl", "-fsSL", url, "-o", str(dest)])
    if r.returncode != 0:
        print(f"Failed to fetch: {url}", file=sys.stderr)
        sys.exit(2)
    ok += 1
print(f"Downloaded {ok} files from {src}")
PY

for bucket in "${BUCKETS[@]}"; do
  log "Syncing mirror to bucket: ${bucket}"
  aws s3 sync "$TMP_DIR" "s3://${bucket}" --delete --endpoint-url "$ENDPOINT_URL"

  log "Setting no-cache for shell files in ${bucket}"
  aws s3 cp "s3://${bucket}/index.html" "s3://${bucket}/index.html" \
    --metadata-directive REPLACE \
    --cache-control "no-cache, no-store, must-revalidate" \
    --content-type "text/html; charset=utf-8" \
    --endpoint-url "$ENDPOINT_URL"

  aws s3 cp "s3://${bucket}/version.json" "s3://${bucket}/version.json" \
    --metadata-directive REPLACE \
    --cache-control "no-cache, no-store, must-revalidate" \
    --content-type "application/json" \
    --endpoint-url "$ENDPOINT_URL"

  aws s3 cp "s3://${bucket}/flutter_service_worker.js" "s3://${bucket}/flutter_service_worker.js" \
    --metadata-directive REPLACE \
    --cache-control "no-cache, no-store, must-revalidate" \
    --content-type "application/javascript" \
    --endpoint-url "$ENDPOINT_URL"

  aws s3 cp "s3://${bucket}/flutter_bootstrap.js" "s3://${bucket}/flutter_bootstrap.js" \
    --metadata-directive REPLACE \
    --cache-control "no-cache, no-store, must-revalidate" \
    --content-type "application/javascript" \
    --endpoint-url "$ENDPOINT_URL"

  log "Bucket ${bucket} version:"
  aws s3 cp "s3://${bucket}/version.json" - --endpoint-url "$ENDPOINT_URL"
done

log "Done. Verify in browser:"
echo "  ${SRC_HOST}/version.json"
echo "  https://restodocks.ru/version.json"
echo "  https://www.restodocks.ru/version.json"
