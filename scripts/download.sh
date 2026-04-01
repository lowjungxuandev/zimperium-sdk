#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ZDEFEND="${ROOT_DIR}/tmp/zdefend"
cd "$ROOT_DIR"

set -a
source .env
set +a

: "${Request_ID:?Missing Request_ID in .env}"
: "${Token:?Missing Token in .env}"
: "${API_Token:?Missing API_Token in .env}"

BASE_URL="https://devportal.zimperium.com"
mkdir -p "$ZDEFEND"

urlencode() {
  jq -nr --arg v "$1" '$v|@uri'
}

signed_url() {
  local path="$1"
  shift

  local expires raw_query encoded_query signature pair key value
  local -a params=("$@" "token=$Token" "expires=$(( $(date +%s) + 300 ))")

  raw_query="$(printf '%s\n' "${params[@]}" | sort | paste -sd'&' -)"
  signature="$(printf '%s?%s' "$path" "$raw_query" | openssl dgst -sha256 -hmac "$API_Token" | awk '{print $NF}')"

  encoded_query="$(
    while IFS= read -r pair; do
      key="${pair%%=*}"
      value="${pair#*=}"
      printf '%s=%s\n' "$key" "$(urlencode "$value")"
    done < <(printf '%s\n' "${params[@]}" | sort) | paste -sd'&' -
  )"

  printf '%s%s?%s&signature=%s' "$BASE_URL" "$path" "$encoded_query" "$signature"
}

request_json="$(curl -fsS "$(signed_url "/api/request/$Request_ID")")"
status="$(jq -r '.status' <<<"$request_json")"

if [[ "$status" != "completed" ]]; then
  echo "Request $Request_ID status is $status"
  exit 1
fi

while IFS= read -r filename; do
  [[ -n "$filename" ]] || continue
  output="${ZDEFEND}/$filename"
  if [[ -f "$output" ]]; then
    echo "Skipping $output"
    continue
  fi

  echo "Downloading $filename -> $output"
  curl -fS --progress-meter -X POST -o "$output" "$(signed_url "/api/request/download_file" "filename=$filename")"
done < <(jq -r '.files[]' <<<"$request_json")

echo "Done"
