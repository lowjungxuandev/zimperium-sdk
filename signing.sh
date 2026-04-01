#!/bin/bash
# zDefend signing: vendor *defend*.zip -> signed AAR + optional iOS xcframework; removes unzipped source after signing.
# Usage: ./signing.sh [--zip <path>] [--force-unzip] [--help]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_CSV="${ROOT_DIR}/csv/android/zdefend.csv"
IOS_CSV="${ROOT_DIR}/csv/ios/zdefend.csv"
ZDEFEND="${ROOT_DIR}/zdefend"
SOURCE_ROOT="${ZDEFEND}/source"
OUTPUT_DIR="${ZDEFEND}/output"

ZIP_OVERRIDE=""
FORCE_UNZIP=0
build_ios=0

usage() {
  cat <<'EOF'
Usage: ./signing.sh [--zip <vendor.zip>] [--force-unzip] [--help]

Unzips *defend*.zip to zdefend/source/<ver>, runs config_sdk_*.jar, writes
zdefend/output/<ver>/android/ZDefend.aar and optionally iOS ZDefend.xcframework,
then removes zdefend/source/<ver> (unzipped vendor tree) after signing.
EOF
}

die() { echo "Error: $*" >&2; exit 1; }

ensure_dir() { [[ -d "$1" ]] || mkdir -p "$1"; }

check_tools() {
  command -v java >/dev/null 2>&1 || die "java not in PATH"
  command -v unzip >/dev/null 2>&1 || die "unzip not in PATH"
  java -version >/dev/null 2>&1 || die "Java runtime not working (try: java -version)"
}

ensure_csv_template() {
  [[ -f "$1" ]] && return
  printf '%s\n' "license_name,license_key,bundle_id" >"$1"
  echo "Created $1 - add rows under the header." >&2
}

validate_csv_header() {
  local h
  h="$(awk 'NF { gsub(/\r$/,""); print; exit }' "$1")" || true
  [[ -n "$h" ]] || die "Empty CSV: $1"
  [[ "$h" == "license_name,license_key,bundle_id" ]] || die "Bad header in $1"
}

# Prints -k\tname=key\t-b\tbundle per row (after header).
build_flags_from_csv() {
  awk -F',' '
    NR==1 { next }
    /^[[:space:]]*(#|$)/ { next }
    {
      n=$1; k=$2; b=$3
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", n)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", b)
      if (n != "" && b != "") printf "-k\t%s=%s\t-b\t%s\n", n, k, b
    }
  ' "$1"
}

# Fills _FLAG_ARGS from a CSV path (reused for Android / iOS).
load_flag_args() {
  _FLAG_ARGS=()
  local a b c d
  while IFS=$'\t' read -r a b c d; do
    [[ -n "${a:-}" ]] && _FLAG_ARGS+=("$a" "$b" "$c" "$d")
  done < <(build_flags_from_csv "$1")
}

find_vendor_zips() {
  vendor_zips=()
  if [[ -n "$ZIP_OVERRIDE" ]]; then
    [[ -f "$ZIP_OVERRIDE" ]] || die "--zip not found: $ZIP_OVERRIDE"
    vendor_zips+=("$ZIP_OVERRIDE")
    return
  fi
  while IFS= read -r z; do
    [[ -n "$z" ]] && vendor_zips+=("$z")
  done < <(
    {
      find "$ROOT_DIR" -maxdepth 1 -type f -iname "*defend*.zip" ! -iname "*xcframework*" -print 2>/dev/null || true
      [[ -d "$ZDEFEND" ]] && find "$ZDEFEND" -maxdepth 1 -type f -iname "*defend*.zip" ! -iname "*xcframework*" -print 2>/dev/null || true
    } | sort -u
  )
  ((${#vendor_zips[@]})) || die "No *defend*.zip in repo root or zdefend/ (or use --zip)"
}

extract_version() {
  local f base
  f="$(basename "$1")"
  if [[ "$f" =~ [zZ][dD]efend_([0-9]+([.][0-9]+)+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi
  base="${f%.zip}"
  base="${base// /_}"
  base="$(echo "$base" | tr -cd '[:alnum:]._-')"
  echo "${base:-unknown-version}"
}

prepare_source_dir() {
  local zip="$1" ver="$2" dir="${SOURCE_ROOT}/${ver}"
  [[ "$FORCE_UNZIP" -eq 1 ]] && rm -rf "$dir"
  if [[ ! -d "$dir" || -z "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    ensure_dir "$dir"
    unzip -q "$zip" -d "$dir"
  fi
  echo "$dir"
}

sign_one_version() {
  local src="$1" ver="$2"
  local jar aar out zip_signed ios_out

  jar="$(find "$src" -maxdepth 1 -name "config_sdk_*.jar" -print -quit 2>/dev/null || true)"
  [[ -n "$jar" ]] || die "No config_sdk_*.jar in $src"

  aar="$(find "$src/native/android" -name "ZDefend-protected-consumer-release-sdk-*.aar" -print -quit 2>/dev/null || true)"
  [[ -n "$aar" ]] || die "No Android AAR under $src/native/android"

  load_flag_args "$ANDROID_CSV"
  out="${OUTPUT_DIR}/${ver}"
  ensure_dir "${out}/android"

  echo "Android ${ver}..." >&2
  java -jar "$jar" -s "$aar" -o "${out}/android/ZDefend.aar" "${_FLAG_ARGS[@]}"

  if [[ "$build_ios" -eq 1 ]]; then
    load_flag_args "$IOS_CSV"
    zip_signed="$(find "$src/native/ios" -name "ZDefend-protected-consumer-release-sdk-*.xcframework.zip" -print -quit 2>/dev/null || true)"
    [[ -n "$zip_signed" ]] || die "No iOS xcframework zip under $src/native/ios"
    ios_out="${out}/iOS"
    ensure_dir "$ios_out"
    echo "iOS ${ver}..." >&2
    java -jar "$jar" -s "$zip_signed" -o "${out}/ZDefend.xcframework.zip" "${_FLAG_ARGS[@]}"
    rm -rf "${ios_out}/ZDefend.xcframework"
    unzip -q "${out}/ZDefend.xcframework.zip" -d "$ios_out"
    rm -f "${out}/ZDefend.xcframework.zip"
  fi

  rm -rf "$src"
}

main() {
  local vendor_zip ver src
  local -a done_vers=()

  case "${1:-}" in --help|-h) usage; exit 0 ;; esac

  while (($#)); do
    case "$1" in
      --zip) shift; ZIP_OVERRIDE="${1:-}"; [[ -n "$ZIP_OVERRIDE" ]] || die "--zip needs a path" ;;
      --force-unzip) FORCE_UNZIP=1 ;;
      --help|-h) usage; exit 0 ;;
      *) die "Unknown arg: $1" ;;
    esac
    shift || true
  done

  check_tools
  ensure_dir "${ROOT_DIR}/csv/android"
  ensure_dir "$ZDEFEND"

  ensure_csv_template "$ANDROID_CSV"
  validate_csv_header "$ANDROID_CSV"
  [[ "$(build_flags_from_csv "$ANDROID_CSV" | wc -l | tr -d ' ')" -gt 0 ]] || die "No Android signing rows in $ANDROID_CSV"

  if [[ -f "$IOS_CSV" ]]; then
    ensure_dir "${ROOT_DIR}/csv/ios"
    validate_csv_header "$IOS_CSV"
    [[ "$(build_flags_from_csv "$IOS_CSV" | wc -l | tr -d ' ')" -gt 0 ]] && build_ios=1
  fi

  find_vendor_zips

  for vendor_zip in "${vendor_zips[@]}"; do
    ver="$(extract_version "$vendor_zip")"
    src="$(prepare_source_dir "$vendor_zip" "$ver")"
    echo "Signing: $vendor_zip -> $ver" >&2
    sign_one_version "$src" "$ver"
    done_vers+=("$ver")
  done

  echo "" >&2
  echo "Done:" >&2
  for ver in "${done_vers[@]}"; do
    [[ "$build_ios" -eq 1 ]] && echo "  iOS:   ${OUTPUT_DIR}/${ver}/iOS/ZDefend.xcframework" >&2
    echo "  AAR:   ${OUTPUT_DIR}/${ver}/android/ZDefend.aar" >&2
  done
}

main "$@"
