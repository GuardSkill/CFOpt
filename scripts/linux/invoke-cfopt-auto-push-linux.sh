#!/usr/bin/env bash
set -euo pipefail

DOWNLOAD_URL="${DOWNLOAD_URL:-https://zip.cm.edu.kg/ip.zip}"
WORK_DIR="${WORK_DIR:-$HOME/cfopt-auto-push}"
CFST_PATH="${CFST_PATH:-$WORK_DIR/cfst}"
PORT="${PORT:-443}"
DOWNLOAD_TEST_URL="${DOWNLOAD_TEST_URL:-}"
COUNTRIES_CSV="${COUNTRIES_CSV:-HK,KR,SG,PH,VN,MY,KZ,MN,IE,US}"
OWNER="${OWNER:-GuardSkill}"
REPO="${REPO:-CFOpt}"
BRANCH="${BRANCH:-main}"
TARGET_PATH="${TARGET_PATH:-CloudflareSpeedTest_BJ.csv}"
INTERVAL_DAYS="${INTERVAL_DAYS:-6}"
MAX_LATENCY_MS="${MAX_LATENCY_MS:-999}"
MIN_RECEIVED="${MIN_RECEIVED:-1}"
TOKEN_ENV_NAME="${TOKEN_ENV_NAME:-GITHUB_TOKEN_CFOPT}"
FORCE="${FORCE:-0}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_UPLOAD="${SKIP_UPLOAD:-0}"

ZIP_PATH="$WORK_DIR/ip.zip"
TMP_ZIP_PATH="$WORK_DIR/ip.download.zip"
EXTRACT_DIR="$WORK_DIR/extract"
SELECTED_IP_PATH="$WORK_DIR/selected-ip.txt"
CSV_PATH="$WORK_DIR/CloudflareSpeedTest.csv"
STATE_FILE="$WORK_DIR/last-success.txt"
LOG_FILE="$WORK_DIR/auto-push.log"

log() {
  mkdir -p "$WORK_DIR"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

should_run() {
  if [[ "$FORCE" == "1" || "$DRY_RUN" == "1" ]]; then
    return 0
  fi

  if [[ ! -f "$STATE_FILE" ]]; then
    return 0
  fi

  local last_epoch now_epoch next_epoch
  last_epoch="$(date -d "$(cat "$STATE_FILE")" +%s 2>/dev/null || echo 0)"
  now_epoch="$(date +%s)"
  next_epoch=$((last_epoch + INTERVAL_DAYS * 86400))

  if (( now_epoch < next_epoch )); then
    log "Skipped. Last successful run has not reached ${INTERVAL_DAYS} days."
    return 1
  fi

  return 0
}

update_zip_cache() {
  rm -f "$TMP_ZIP_PATH"
  log "Downloading $DOWNLOAD_URL"
  if curl -fL --retry 3 --connect-timeout 20 -o "$TMP_ZIP_PATH" "$DOWNLOAD_URL"; then
    mv "$TMP_ZIP_PATH" "$ZIP_PATH"
    log "Downloaded zip cache: $ZIP_PATH"
    return 0
  fi

  rm -f "$TMP_ZIP_PATH"
  if [[ -f "$ZIP_PATH" ]]; then
    log "WARN: Download failed. Reusing existing zip cache: $ZIP_PATH"
    return 0
  fi

  log "ERROR: Download failed and no zip cache exists."
  return 1
}

merge_country_files() {
  local port_dir="$EXTRACT_DIR/$PORT"
  if [[ ! -d "$port_dir" ]]; then
    log "ERROR: Port folder not found in extracted zip: $port_dir"
    return 1
  fi

  log "Using IP files from zip port folder: $port_dir"
  : > "$SELECTED_IP_PATH"

  IFS=',' read -r -a countries <<< "$COUNTRIES_CSV"
  local found=0
  for country in "${countries[@]}"; do
    local file="$port_dir/${country}.txt"
    if [[ ! -f "$file" ]]; then
      log "WARN: Country file not found in extracted zip: ${country}.txt. Skipping $country."
      continue
    fi
    grep -vE '^[[:space:]]*(#|$)' "$file" >> "$SELECTED_IP_PATH" || true
    found=$((found + 1))
  done

  local line_count
  line_count="$(grep -vcE '^[[:space:]]*(#|$)' "$SELECTED_IP_PATH" || true)"
  if (( found == 0 || line_count == 0 )); then
    log "ERROR: No usable country IP lines found."
    return 1
  fi

  log "Merged $line_count IP lines into $SELECTED_IP_PATH."
}

run_cfst() {
  if [[ ! -x "$CFST_PATH" ]]; then
    log "ERROR: cfst executable not found or not executable: $CFST_PATH"
    return 1
  fi

  rm -f "$CSV_PATH"
  local args=(-f "$SELECTED_IP_PATH" -o "$CSV_PATH")
  if [[ "$PORT" != "443" ]]; then
    args+=(-tp "$PORT")
  fi
  if [[ -n "$DOWNLOAD_TEST_URL" ]]; then
    args+=(-url "$DOWNLOAD_TEST_URL")
  fi

  log "Running cfst: $CFST_PATH ${args[*]}"
  printf '\n' | "$CFST_PATH" "${args[@]}" > "$WORK_DIR/cfst-stdout.log" 2> "$WORK_DIR/cfst-stderr.log"
  sed 's/^/cfst: /' "$WORK_DIR/cfst-stdout.log" | tee -a "$LOG_FILE" >/dev/null || true
  sed 's/^/cfst stderr: /' "$WORK_DIR/cfst-stderr.log" | tee -a "$LOG_FILE" >/dev/null || true

  if [[ ! -f "$CSV_PATH" ]]; then
    log "ERROR: cfst completed but CSV was not created: $CSV_PATH"
    return 1
  fi
}

filter_csv() {
  local tmp_csv="$CSV_PATH.filtered"
  awk -F',' -v max_latency="$MAX_LATENCY_MS" -v min_received="$MIN_RECEIVED" '
    NR == 1 { print; next }
    NF < 5 { removed++; next }
    {
      received = $3 + 0
      loss = $4 + 0
      latency = $5 + 0
      if (received >= min_received && loss < 1 && latency <= max_latency) {
        print
        kept++
      } else {
        removed++
      }
    }
    END {
      if (kept < 1) {
        exit 2
      }
    }
  ' "$CSV_PATH" > "$tmp_csv"
  mv "$tmp_csv" "$CSV_PATH"
  local kept
  kept=$(( $(wc -l < "$CSV_PATH") - 1 ))
  log "Filtered CSV rows. Kept $kept. Rules: received >= $MIN_RECEIVED, loss < 1, latency <= $MAX_LATENCY_MS ms."
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

publish_to_github() {
  local token="${!TOKEN_ENV_NAME:-}"
  if [[ -z "$token" ]]; then
    log "ERROR: Missing GitHub token. Set $TOKEN_ENV_NAME."
    return 1
  fi

  local encoded_path
  encoded_path="$(python3 - "$TARGET_PATH" <<'PY'
import sys, urllib.parse
print("/".join(urllib.parse.quote(part, safe="") for part in sys.argv[1].split("/")))
PY
)"
  local uri="https://api.github.com/repos/$OWNER/$REPO/contents/$encoded_path"
  local meta_file="$WORK_DIR/github-meta.json"
  local status
  status="$(curl -sS -o "$meta_file" -w '%{http_code}' \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$uri?ref=$BRANCH")"

  local sha=""
  if [[ "$status" == "200" ]]; then
    sha="$(python3 - "$meta_file" <<'PY'
import json,sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["sha"])
PY
)"
    log "GitHub file exists. Upload will update existing file."
  elif [[ "$status" == "404" ]]; then
    log "GitHub file was not found. Upload will create a new file."
  else
    log "ERROR: GitHub metadata request failed with HTTP $status."
    cat "$meta_file" >> "$LOG_FILE" || true
    return 1
  fi

  local content message body_file response_file put_status
  content="$(base64 -w 0 "$CSV_PATH")"
  message="Update $TARGET_PATH"
  body_file="$WORK_DIR/github-upload.json"
  response_file="$WORK_DIR/github-upload-response.json"
  python3 - "$message" "$content" "$BRANCH" "$sha" > "$body_file" <<'PY'
import json,sys
message, content, branch, sha = sys.argv[1:5]
body = {"message": message, "content": content, "branch": branch}
if sha:
    body["sha"] = sha
print(json.dumps(body))
PY

  put_status="$(curl -sS -o "$response_file" -w '%{http_code}' -X PUT \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    --data-binary "@$body_file" \
    "$uri")"

  if [[ "$put_status" != "200" && "$put_status" != "201" ]]; then
    log "ERROR: GitHub upload failed with HTTP $put_status."
    cat "$response_file" >> "$LOG_FILE" || true
    return 1
  fi

  log "Uploaded $CSV_PATH to $OWNER/$REPO/$TARGET_PATH."
}

main() {
  mkdir -p "$WORK_DIR"
  log "Starting CFOpt Linux auto push."
  should_run || exit 0

  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"

  update_zip_cache
  log "Extracting $ZIP_PATH"
  unzip -oq "$ZIP_PATH" -d "$EXTRACT_DIR"
  merge_country_files

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Dry run enabled. Skipping cfst execution and GitHub upload."
    exit 0
  fi

  run_cfst
  filter_csv

  if [[ "$SKIP_UPLOAD" == "1" ]]; then
    log "SkipUpload enabled. CSV generated but GitHub upload and success-state update were skipped."
    exit 0
  fi

  publish_to_github
  date --iso-8601=seconds > "$STATE_FILE"
  log "Completed successfully."
}

main "$@"
