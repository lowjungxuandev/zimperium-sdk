#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ZDEFEND="${ROOT_DIR}/tmp/zdefend"
CONFIG_DIR="${ZDEFEND}/config"
cd "$ROOT_DIR"

mkdir -p "$CONFIG_DIR"

to_json() {
  local csv_file="$1"
  local json_file="$2"
  local platform="$3"

  awk -F',' '
    NR == 1 { next }
    /^[[:space:]]*(#|$)/ { next }
    {
      gsub(/\r$/, "", $3)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
      if ($1 != "" && $3 != "") printf "%s\t%s\t%s\n", $1, $2, $3
    }
  ' "$csv_file" | jq -Rn --arg platform "$platform" '
    [inputs
     | split("\t")
     | {
         license_name: .[0],
         license_key: .[1],
         bundle_id: .[2]
       }]
    | { platform: $platform, entries: . }
  ' >"$json_file"
}

to_json "${ROOT_DIR}/csv/android/zdefend.csv" "${CONFIG_DIR}/android.json" "android"

if [[ -f "${ROOT_DIR}/csv/ios/zdefend.csv" ]]; then
  to_json "${ROOT_DIR}/csv/ios/zdefend.csv" "${CONFIG_DIR}/ios.json" "ios"
fi

echo "Wrote ${CONFIG_DIR}/android.json"
[[ -f "${CONFIG_DIR}/ios.json" ]] && echo "Wrote ${CONFIG_DIR}/ios.json"
