#!/usr/bin/env bash
set -euo pipefail

DOWNLOAD_URL="${DOWNLOAD_URL:-https://zip.cm.edu.kg/ip.zip}"
WORK_DIR="${WORK_DIR:-$HOME/cfopt-auto-push}"
CFST_PATH="${CFST_PATH:-$WORK_DIR/cfst}"
PORT="${PORT:-}"
PORTS="${PORTS:-443,2053,2083,2087,2096,8443}"
DOWNLOAD_TEST_URL="${DOWNLOAD_TEST_URL:-https://speed.cloudflare.com/__down?bytes=100000000}"
COUNTRIES_CSV="${COUNTRIES_CSV:-HK,KR,SG,PH,VN,MY,KZ,MN,IE,US}"
OWNER="${OWNER:-GuardSkill}"
REPO="${REPO:-CFOpt}"
BRANCH="${BRANCH:-main}"
TARGET_PATH="${TARGET_PATH:-CloudflareSpeedTest_BJ.csv}"
INTERVAL_DAYS="${INTERVAL_DAYS:-3}"
MAX_LATENCY_MS="${MAX_LATENCY_MS:-420}"
MIN_RECEIVED="${MIN_RECEIVED:-1}"
MIN_SPEED_MBPS="${MIN_SPEED_MBPS:-0.01}"
MAX_PER_CITY="${MAX_PER_CITY:-20}"
TOKEN_ENV_NAME="${TOKEN_ENV_NAME:-GITHUB_TOKEN_CFOPT}"
FORCE="${FORCE:-0}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_UPLOAD="${SKIP_UPLOAD:-0}"
CFST_DEBUG="${CFST_DEBUG:-0}"

ZIP_PATH="$WORK_DIR/ip.zip"
TMP_ZIP_PATH="$WORK_DIR/ip.download.zip"
EXTRACT_DIR="$WORK_DIR/extract"
CSV_PATH="$WORK_DIR/CloudflareSpeedTest.csv"
COMBINED_CANDIDATES_PATH="$WORK_DIR/CloudflareSpeedTest.candidates.csv"
STATE_FILE="$WORK_DIR/last-success.txt"
LOG_FILE="$WORK_DIR/auto-push.log"

log() {
  mkdir -p "$WORK_DIR"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

effective_ports() {
  if [[ -n "$PORT" ]]; then
    printf '%s\n' "$PORT"
  else
    tr ',' '\n' <<< "$PORTS" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | awk 'NF && !seen[$0]++'
  fi
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

merge_country_files_for_port() {
  local port="$1"
  local port_dir="$EXTRACT_DIR/$port"
  local selected_ip_path="$WORK_DIR/selected-ip-$port.txt"
  local map_path="$WORK_DIR/selected-ip-city-map-$port.csv"

  if [[ ! -d "$port_dir" ]]; then
    log "WARN: Port folder not found in extracted zip: $port_dir. Skipping port $port."
    return 1
  fi

  log "Using IP files from zip port folder: $port_dir"
  : > "$selected_ip_path"
  : > "$map_path"

  IFS=',' read -r -a countries <<< "$COUNTRIES_CSV"
  local found=0
  for country in "${countries[@]}"; do
    local file="$port_dir/${country}.txt"
    if [[ ! -f "$file" ]]; then
      log "WARN: Country file not found in extracted zip: ${country}.txt. Skipping $country on port $port."
      continue
    fi
    grep -vE '^[[:space:]]*(#|$)' "$file" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' >> "$selected_ip_path" || true
    grep -vE '^[[:space:]]*(#|$)' "$file" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | awk -v city="$country" 'NF { print $0 "," city }' >> "$map_path" || true
    found=$((found + 1))
  done

  local line_count
  line_count="$(grep -vcE '^[[:space:]]*(#|$)' "$selected_ip_path" || true)"
  if (( found == 0 || line_count == 0 )); then
    log "WARN: No usable country IP lines found for port $port."
    return 1
  fi

  log "Merged $line_count IP lines for port $port into $selected_ip_path."
  printf '%s,%s,%s\n' "$port" "$selected_ip_path" "$map_path" >> "$WORK_DIR/port-work-items.csv"
}

start_cfst_for_port() {
  local port="$1"
  local selected_ip_path="$2"
  local csv_path="$WORK_DIR/CloudflareSpeedTest-$port.csv"
  local stdout_path="$WORK_DIR/cfst-$port-stdout.log"
  local stderr_path="$WORK_DIR/cfst-$port-stderr.log"
  local args=(-f "$selected_ip_path" -o "$csv_path")

  if [[ "$port" != "443" ]]; then
    args+=(-tp "$port")
  fi
  if [[ -n "$DOWNLOAD_TEST_URL" ]]; then
    args+=(-url "$DOWNLOAD_TEST_URL")
  fi
  if awk "BEGIN { exit !($MIN_SPEED_MBPS > 0) }"; then
    args+=(-sl "$MIN_SPEED_MBPS")
  fi
  if [[ "$CFST_DEBUG" == "1" ]]; then
    args+=(-debug)
  fi

  rm -f "$csv_path" "$stdout_path" "$stderr_path"
  log "Starting cfst on port $port: $CFST_PATH ${args[*]}"
  (printf '\n' | "$CFST_PATH" "${args[@]}" > "$stdout_path" 2> "$stderr_path") &
  printf '%s,%s,%s,%s\n' "$port" "$!" "$csv_path" "$selected_ip_path" >> "$WORK_DIR/cfst-processes.csv"
}

wait_cfst_processes() {
  local failed=0
  while IFS=',' read -r port pid csv_path _selected_ip_path; do
    if ! wait "$pid"; then
      log "ERROR: cfst failed on port $port."
      failed=1
    fi
    [[ -f "$WORK_DIR/cfst-$port-stdout.log" ]] && sed "s/^/cfst[$port]: /" "$WORK_DIR/cfst-$port-stdout.log" | tee -a "$LOG_FILE" >/dev/null || true
    [[ -f "$WORK_DIR/cfst-$port-stderr.log" ]] && sed "s/^/cfst[$port] stderr: /" "$WORK_DIR/cfst-$port-stderr.log" | tee -a "$LOG_FILE" >/dev/null || true
    if [[ ! -f "$csv_path" ]]; then
      log "ERROR: cfst completed but CSV was not created for port $port: $csv_path"
      failed=1
    fi
  done < "$WORK_DIR/cfst-processes.csv"

  return "$failed"
}

build_combined_candidates() {
  : > "$COMBINED_CANDIDATES_PATH"
  while IFS=',' read -r port _selected_ip_path map_path; do
    local csv_path="$WORK_DIR/CloudflareSpeedTest-$port.csv"
    [[ -f "$csv_path" ]] || continue
    awk -F',' -v port="$port" '
      FNR == NR {
        if (NF >= 2 && !($1 in city_by_ip)) city_by_ip[$1] = $2
        next
      }
      FNR == 1 { next }
      NF >= 6 {
        ip = $1
        city = city_by_ip[ip]
        print port "," city "," $0
      }
    ' "$map_path" "$csv_path" >> "$COMBINED_CANDIDATES_PATH"
  done < "$WORK_DIR/port-work-items.csv"
}

filter_csv() {
  local tmp_csv="$CSV_PATH.filtered"
  if ! awk -F',' -v max_latency="$MAX_LATENCY_MS" -v min_received="$MIN_RECEIVED" -v min_speed_mbps="$MIN_SPEED_MBPS" -v max_per_city="$MAX_PER_CITY" '
    {
      port = $1
      city = $2
      ip = $3
      sent = $4
      received = $5 + 0
      loss = $6 + 0
      latency = $7 + 0
      speed = $8 + 0
      datacenter = $9
      speed_mbps = speed * 8
      if (received >= min_received && loss < 1 && latency <= max_latency && speed_mbps >= min_speed_mbps) {
        remark = sprintf("%s [%.0fms %.2fMbps]", city, latency, speed_mbps)
        row = sprintf("%s,%s,%s,%s,true,%s,%s,%s,%s,%s", ip, port, datacenter, remark, sent, received, loss, latency, speed)
        rows[++count] = sprintf("%s\t%012.6f\t%012.6f\t%s", city, 999999-speed, latency, row)
        kept++
      } else {
        removed++
      }
    }
    END {
      if (kept < 1) exit 2
      print "IP地址,端口,数据中心,城市,TLS,已发送,已接收,丢包率,平均延迟,下载速度(MB/s)"
      for (i = 1; i <= count; i++) {
        for (j = i + 1; j <= count; j++) {
          if (rows[j] < rows[i]) {
            tmp = rows[i]; rows[i] = rows[j]; rows[j] = tmp
          }
        }
      }
      current_city = ""
      city_count = 0
      for (i = 1; i <= count; i++) {
        split(rows[i], parts, "\t")
        city = parts[1]
        if (city != current_city) {
          current_city = city
          city_count = 0
        }
        if (city_count < max_per_city) {
          print parts[4]
          city_count++
        }
      }
    }
  ' "$COMBINED_CANDIDATES_PATH" > "$tmp_csv"; then
    log "ERROR: Filtering removed all CSV rows. Check MAX_LATENCY_MS=$MAX_LATENCY_MS, MIN_RECEIVED=$MIN_RECEIVED, and MIN_SPEED_MBPS=$MIN_SPEED_MBPS. If cfst reports 0.00 MB/s, rerun with CFST_DEBUG=1."
    rm -f "$tmp_csv"
    return 1
  fi
  if [[ ! -s "$tmp_csv" ]]; then
    log "ERROR: Filtering removed all CSV rows. Check MAX_LATENCY_MS=$MAX_LATENCY_MS, MIN_RECEIVED=$MIN_RECEIVED, and MIN_SPEED_MBPS=$MIN_SPEED_MBPS. If cfst reports 0.00 MB/s, rerun with CFST_DEBUG=1."
    rm -f "$tmp_csv"
    return 1
  fi
  mv "$tmp_csv" "$CSV_PATH"
  local kept
  kept=$(( $(wc -l < "$CSV_PATH") - 1 ))
  log "Merged and filtered CSV rows across ports. Kept $kept. Top $MAX_PER_CITY per city/group. Rules: received >= $MIN_RECEIVED, loss < 1, latency <= $MAX_LATENCY_MS ms, speed >= $MIN_SPEED_MBPS Mbps."
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

  if [[ ! -x "$CFST_PATH" && "$DRY_RUN" != "1" ]]; then
    log "ERROR: cfst executable not found or not executable: $CFST_PATH"
    exit 1
  fi

  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"
  rm -f "$WORK_DIR/port-work-items.csv" "$WORK_DIR/cfst-processes.csv" "$COMBINED_CANDIDATES_PATH" "$CSV_PATH"

  update_zip_cache
  log "Extracting $ZIP_PATH"
  unzip -oq "$ZIP_PATH" -d "$EXTRACT_DIR"

  mapfile -t ports < <(effective_ports)
  log "Configured ports: ${ports[*]}"
  for port_value in "${ports[@]}"; do
    merge_country_files_for_port "$port_value" || true
  done

  if [[ ! -s "$WORK_DIR/port-work-items.csv" ]]; then
    log "ERROR: No usable port/country inputs were prepared."
    exit 1
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Dry run enabled. Skipping cfst execution and GitHub upload."
    while IFS=',' read -r port_value selected_ip_path _map_path; do
      args=(-f "$selected_ip_path" -o "$WORK_DIR/CloudflareSpeedTest-$port_value.csv")
      [[ "$port_value" != "443" ]] && args+=(-tp "$port_value")
      [[ -n "$DOWNLOAD_TEST_URL" ]] && args+=(-url "$DOWNLOAD_TEST_URL")
      if awk "BEGIN { exit !($MIN_SPEED_MBPS > 0) }"; then
        args+=(-sl "$MIN_SPEED_MBPS")
      fi
      [[ "$CFST_DEBUG" == "1" ]] && args+=(-debug)
      log "Would run: $CFST_PATH ${args[*]}"
    done < "$WORK_DIR/port-work-items.csv"
    exit 0
  fi

  while IFS=',' read -r port_value selected_ip_path _map_path; do
    start_cfst_for_port "$port_value" "$selected_ip_path"
  done < "$WORK_DIR/port-work-items.csv"

  wait_cfst_processes
  build_combined_candidates
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
