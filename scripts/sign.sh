#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ZDEFEND="${ROOT_DIR}/tmp/zdefend"
ANDROID_JSON="${ZDEFEND}/config/android.json"
IOS_JSON="${ZDEFEND}/config/ios.json"
SOURCE_DIR="${ZDEFEND}/source"
OUTPUT_DIR="${ZDEFEND}/output"
cd "$ROOT_DIR"

mkdir -p "$SOURCE_DIR" "$OUTPUT_DIR"

load_flags() {
  local json_file="$1"
  FLAG_ARGS=()
  while IFS=$'\t' read -r name key bundle; do
    [[ -n "$name" && -n "$bundle" ]] || continue
    FLAG_ARGS+=("-k" "${name}=${key}" "-b" "$bundle")
  done < <(jq -r '.entries[] | [.license_name, .license_key, .bundle_id] | @tsv' "$json_file")
}

if [[ $# -gt 0 ]]; then
  zips=("$1")
else
  zips=()
  while IFS= read -r zip_file; do
    [[ -n "$zip_file" ]] || continue
    zips+=("$zip_file")
  done < <(find "$ZDEFEND" -maxdepth 1 -type f -iname "*defend*.zip" ! -iname "*xcframework*" 2>/dev/null | sort -u)
fi

[[ -f "$ANDROID_JSON" ]] || { echo "Missing $ANDROID_JSON. Run ./scripts/csv.sh first."; exit 1; }
[[ ${#zips[@]} -gt 0 ]] || { echo "No zDefend zip found."; exit 1; }

has_ios=0
[[ -f "$IOS_JSON" && "$(jq '.entries | length' "$IOS_JSON")" -gt 0 ]] && has_ios=1

for zip_file in "${zips[@]}"; do
  base="$(basename "$zip_file" .zip)"
  version="$base"
  if [[ "$base" =~ [zZ][dD]efend_([0-9]+([.][0-9]+)+) ]]; then
    version="${BASH_REMATCH[1]}"
  fi

  src="${SOURCE_DIR}/${version}"
  out="${OUTPUT_DIR}/${version}"

  rm -rf "$src"
  mkdir -p "$src" "${out}/android"
  unzip -q "$zip_file" -d "$src"

  jar="$(find "$src" -maxdepth 1 -name 'config_sdk_*.jar' -print -quit)"
  aar="$(find "$src/native/android" -name 'ZDefend-protected-consumer-release-sdk-*.aar' -print -quit)"

  load_flags "$ANDROID_JSON"
  java -jar "$jar" -s "$aar" -o "${out}/android/ZDefend.aar" "${FLAG_ARGS[@]}"

  if [[ "$has_ios" -eq 1 ]]; then
    ios_zip="$(find "$src/native/ios" -name 'ZDefend-protected-consumer-release-sdk-*.xcframework.zip' -print -quit)"
    if [[ -n "$ios_zip" ]]; then
      mkdir -p "${out}/iOS"
      load_flags "$IOS_JSON"
      java -jar "$jar" -s "$ios_zip" -o "${out}/ZDefend.xcframework.zip" "${FLAG_ARGS[@]}"
      rm -rf "${out}/iOS/ZDefend.xcframework"
      unzip -q "${out}/ZDefend.xcframework.zip" -d "${out}/iOS"
      rm -f "${out}/ZDefend.xcframework.zip"
    fi
  fi

  rm -rf "$src"
  echo "Done ${version}"
done
