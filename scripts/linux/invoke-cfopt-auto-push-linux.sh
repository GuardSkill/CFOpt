#!/usr/bin/env bash
set -euo pipefail

DOWNLOAD_URL="${DOWNLOAD_URL:-https://zip.cm.edu.kg/ip.zip}"
WORK_DIR="${WORK_DIR:-$HOME/cfopt-auto-push}"
CFST_PATH="${CFST_PATH:-$WORK_DIR/cfst}"
PORT="${PORT:-}"
PORTS="${PORTS:-443,2053,2083,2087,2096,8443}"
DOWNLOAD_TEST_URL="${DOWNLOAD_TEST_URL:-https://cf.xiu2.xyz/url}"
COUNTRIES_CSV="${COUNTRIES_CSV:-HK,JP,KR,SG,PH,VN,MY,KZ,MN,IE,US}"
OWNER="${OWNER:-GuardSkill}"
REPO="${REPO:-CFOpt}"
BRANCH="${BRANCH:-main}"
TARGET_PATH="${TARGET_PATH:-CloudflareSpeedTest_BJ.csv}"
INTERVAL_DAYS="${INTERVAL_DAYS:-1}"
MAX_LATENCY_MS="${MAX_LATENCY_MS:-420}"
MIN_RECEIVED="${MIN_RECEIVED:-1}"
MIN_SPEED_MBPS="${MIN_SPEED_MBPS:-0.01}"
MAX_PER_CITY="${MAX_PER_CITY:-20}"
ROLLING_REPLACE_FRACTION="${ROLLING_REPLACE_FRACTION:-0.33}"
CFST_THREADS="${CFST_THREADS:-160}"
CFST_LATENCY_TEST_COUNT="${CFST_LATENCY_TEST_COUNT:-6}"
CFST_DOWNLOAD_TEST_COUNT="${CFST_DOWNLOAD_TEST_COUNT:-60}"
CFST_DOWNLOAD_TEST_TIME="${CFST_DOWNLOAD_TEST_TIME:-15}"
CFST_LOSS_RATE_LIMIT="${CFST_LOSS_RATE_LIMIT:-0}"
MAX_PARALLEL_CFST="${MAX_PARALLEL_CFST:-3}"
USE_PROXY_FOR_CFST="${USE_PROXY_FOR_CFST:-0}"
FOCUS_COUNTRIES_CSV="${FOCUS_COUNTRIES_CSV:-HK,JP}"
TEST_LOCATION_NAME="${TEST_LOCATION_NAME:-}"
ENABLE_CFBESTIP="${ENABLE_CFBESTIP:-1}"
CFBESTIP_BASE_URL="${CFBESTIP_BASE_URL:-https://zoroaaa.github.io/cf-bestip}"
CFBESTIP_PER_COUNTRY_LIMIT="${CFBESTIP_PER_COUNTRY_LIMIT:-200}"
ENABLE_VPS789_CT="${ENABLE_VPS789_CT:-0}"
VPS789_CT_LIMIT="${VPS789_CT_LIMIT:-50}"
VPS789_MAX_DX_LATENCY_MS="${VPS789_MAX_DX_LATENCY_MS:-260}"
VPS789_MAX_DX_LOSS_RATE="${VPS789_MAX_DX_LOSS_RATE:-5}"
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
PREVIOUS_CSV_PATH="$WORK_DIR/previous-CloudflareSpeedTest.csv"
PREVIOUS_NODES_PATH="$WORK_DIR/previous-nodes.csv"
PREVIOUS_NODE_KEYS_PATH="$WORK_DIR/previous-node-keys.txt"
VPS789_CT_IP_PATH="$WORK_DIR/vps789-ct-ip.txt"
VPS789_CT_CSV_PATH="$WORK_DIR/VPS789_CF_CT_Candidates.csv"
STATE_FILE="$WORK_DIR/last-success.txt"
LOG_FILE="$WORK_DIR/auto-push.log"

if [[ -z "$TEST_LOCATION_NAME" ]]; then
  TEST_LOCATION_NAME=$'\u5317\u4eac\u6d4b\u901f'
fi

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

fetch_previous_csv_nodes() {
  : > "$PREVIOUS_NODES_PATH"
  : > "$PREVIOUS_NODE_KEYS_PATH"

  local raw_url="https://raw.githubusercontent.com/$OWNER/$REPO/$BRANCH/$TARGET_PATH"
  log "Fetching previous CSV for rolling retest: $raw_url"
  if ! curl -fsSL --retry 2 --connect-timeout 20 -o "$PREVIOUS_CSV_PATH" "$raw_url"; then
    log "WARN: Failed to fetch previous CSV for rolling retest."
    return 0
  fi

  python3 - "$PREVIOUS_CSV_PATH" "$PREVIOUS_NODES_PATH" "$PREVIOUS_NODE_KEYS_PATH" <<'PY'
import csv
import re
import sys

csv_path, nodes_path, keys_path = sys.argv[1:4]
city_re = re.compile(r"^([A-Za-z0-9_-]+)")
rows = []

with open(csv_path, "r", encoding="utf-8-sig", newline="") as f:
    reader = csv.reader(f)
    next(reader, None)
    for row in reader:
        if len(row) < 4:
            continue
        ip = row[0].strip()
        port = row[1].strip()
        city_text = row[3].strip()
        match = city_re.match(city_text)
        if not match:
            continue
        city = match.group(1).upper()
        if re.match(r"^(?:\d{1,3}\.){3}\d{1,3}$", ip) and port.isdigit():
            rows.append((ip, port, city))

with open(nodes_path, "w", encoding="ascii", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(rows)

with open(keys_path, "w", encoding="ascii", newline="") as f:
    for ip, port, city in rows:
        f.write(f"{ip}|{port}|{city}\n")
PY

  local count
  count="$(wc -l < "$PREVIOUS_NODES_PATH" | tr -d ' ')"
  log "Loaded $count previous CSV nodes for rolling retest."
}

fetch_vps789_ct_ips() {
  : > "$VPS789_CT_IP_PATH"
  printf 'No,IP,Line,DXLatencyMs,DXLossRate,LTLatencyMs,LTLossRate,YDLatencyMs,YDLossRate,UpdatedAt,Remark\n' > "$VPS789_CT_CSV_PATH"

  if [[ "$ENABLE_VPS789_CT" != "1" ]]; then
    log "vps789 CT candidate source disabled."
    return 0
  fi

  local json_path="$WORK_DIR/vps789-cfIpApi.json"
  log "Fetching vps789 Cloudflare CT candidates."
  if ! curl -fsSL --retry 2 --connect-timeout 20 -o "$json_path" "https://vps789.com/openApi/cfIpApi"; then
    log "WARN: Failed to fetch vps789 CT candidates."
    return 0
  fi

  if ! python3 - "$json_path" "$VPS789_CT_IP_PATH" "$VPS789_CT_CSV_PATH" "$VPS789_CT_LIMIT" "$VPS789_MAX_DX_LATENCY_MS" "$VPS789_MAX_DX_LOSS_RATE" <<'PY'
import csv
import json
import re
import sys

json_path, ip_path, csv_path = sys.argv[1:4]
limit = int(sys.argv[4])
max_latency = float(sys.argv[5])
max_loss = float(sys.argv[6])
ip_re = re.compile(r"^(?:\d{1,3}\.){3}\d{1,3}$")

with open(json_path, "r", encoding="utf-8") as f:
    payload = json.load(f)

rows = payload.get("data", {}).get("CT", []) or []
filtered = []
for row in rows:
    ip = str(row.get("ip", "")).strip()
    try:
        dx_latency = float(row.get("dxLatencyAvg", 999999))
        dx_loss = float(row.get("dxPkgLostRateAvg", 999999))
        avg_score = float(row.get("avgScore", 999999))
    except (TypeError, ValueError):
        continue
    if ip_re.match(ip) and dx_latency <= max_latency and dx_loss <= max_loss:
        filtered.append((dx_loss, dx_latency, avg_score, row))

filtered.sort(key=lambda item: (item[0], item[1], item[2]))
seen = set()
kept = []
for _, _, _, row in filtered:
    ip = str(row.get("ip", "")).strip()
    if ip in seen:
        continue
    seen.add(ip)
    kept.append(row)
    if len(kept) >= limit:
        break

with open(ip_path, "w", encoding="ascii", newline="") as f:
    for row in kept:
        f.write(str(row.get("ip", "")).strip() + "\n")

with open(csv_path, "w", encoding="utf-8", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["No", "IP", "Line", "DXLatencyMs", "DXLossRate", "LTLatencyMs", "LTLossRate", "YDLatencyMs", "YDLossRate", "UpdatedAt", "Remark"])
    for idx, row in enumerate(kept, start=1):
        writer.writerow([
            f"CT{idx:02d}",
            row.get("ip", ""),
            "CT",
            row.get("dxLatencyAvg", ""),
            row.get("dxPkgLostRateAvg", ""),
            row.get("ltLatencyAvg", ""),
            row.get("ltPkgLostRateAvg", ""),
            row.get("ydLatencyAvg", ""),
            row.get("ydPkgLostRateAvg", ""),
            row.get("createdTime", ""),
            "vps789-ct",
        ])
PY
  then
    log "WARN: Failed to parse vps789 CT candidates."
    : > "$VPS789_CT_IP_PATH"
    return 0
  fi

  local count
  count="$(grep -vcE '^[[:space:]]*(#|$)' "$VPS789_CT_IP_PATH" || true)"
  log "Fetched $count vps789 CT candidates. Exported $VPS789_CT_CSV_PATH."
}

append_cfbestip_for_port() {
  local port="$1"
  local countries_csv="$2"
  local selected_ip_path="$3"
  local map_path="$4"
  local added=0

  if [[ "$ENABLE_CFBESTIP" != "1" ]]; then
    printf '0\n'
    return 0
  fi

  IFS=',' read -r -a cfbestip_countries <<< "$countries_csv"
  for country in "${cfbestip_countries[@]}"; do
    country="$(printf '%s' "$country" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:lower:]' '[:upper:]')"
    [[ -n "$country" ]] || continue

    local url="${CFBESTIP_BASE_URL%/}/ip_${country}.txt"
    local tmp_path="$WORK_DIR/cfbestip-${country}.txt"
    if ! curl -fsSL --retry 2 --connect-timeout 20 -o "$tmp_path" "$url" 2>/dev/null; then
      log "WARN: Failed to fetch cf-bestip candidates for $country: $url" >/dev/null
      continue
    fi

    local count_for_country=0
    while IFS= read -r ip; do
      [[ -n "$ip" ]] || continue
      if ! grep -Fxq "$ip" "$selected_ip_path"; then
        printf '%s\n' "$ip" >> "$selected_ip_path"
        added=$((added + 1))
        count_for_country=$((count_for_country + 1))
      fi
      printf '%s,%s,cf-bestip\n' "$ip" "$country" >> "$map_path"
    done < <(awk -F'[:#]' -v port="$port" -v limit="$CFBESTIP_PER_COUNTRY_LIMIT" 'NF >= 3 && $2 == port && count < limit { print $1; count++ }' "$tmp_path")
    log "Fetched $count_for_country cf-bestip candidates for $country on port $port." >/dev/null
  done

  printf '%s\n' "$added"
}

append_previous_for_port() {
  local port="$1"
  local countries_csv="$2"
  local selected_ip_path="$3"
  local map_path="$4"
  local added=0

  [[ -s "$PREVIOUS_NODES_PATH" ]] || {
    printf '0\n'
    return 0
  }

  local countries_pattern
  countries_pattern="$(tr ',' '\n' <<< "$countries_csv" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:lower:]' '[:upper:]' | awk 'NF { printf "%s%s", sep, $0; sep="|" }')"
  [[ -n "$countries_pattern" ]] || {
    printf '0\n'
    return 0
  }

  while IFS=',' read -r ip prev_port city; do
    [[ "$prev_port" == "$port" ]] || continue
    [[ "$city" =~ ^($countries_pattern)$ ]] || continue
    if ! grep -Fxq "$ip" "$selected_ip_path"; then
      printf '%s\n' "$ip" >> "$selected_ip_path"
      printf '%s,%s,previous\n' "$ip" "$city" >> "$map_path"
      added=$((added + 1))
    fi
  done < "$PREVIOUS_NODES_PATH"

  printf '%s\n' "$added"
}

merge_country_files_for_port() {
  local port="$1"
  local scope="${2:-all}"
  local countries_csv="${3:-$COUNTRIES_CSV}"
  local include_vps789="${4:-1}"
  local safe_scope="${scope//[^A-Za-z0-9_-]/_}"
  local port_dir="$EXTRACT_DIR/$port"
  local selected_ip_path="$WORK_DIR/selected-ip-$port-$safe_scope.txt"
  local map_path="$WORK_DIR/selected-ip-city-map-$port-$safe_scope.csv"

  if [[ ! -d "$port_dir" ]]; then
    log "WARN: Port folder not found in extracted zip: $port_dir. Skipping port $port."
    return 1
  fi

  log "Using IP files from zip port folder: $port_dir"
  : > "$selected_ip_path"
  : > "$map_path"

  IFS=',' read -r -a countries <<< "$countries_csv"
  local found=0
  for country in "${countries[@]}"; do
    local file="$port_dir/${country}.txt"
    if [[ ! -f "$file" ]]; then
      log "WARN: Country file not found in extracted zip: ${country}.txt. Skipping $country on port $port."
      continue
    fi
    grep -vE '^[[:space:]]*(#|$)' "$file" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' >> "$selected_ip_path" || true
    grep -vE '^[[:space:]]*(#|$)' "$file" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | awk -v city="$country" 'NF { print $0 "," city ",ip.zip" }' >> "$map_path" || true
    found=$((found + 1))
  done

  local previous_added
  previous_added="$(append_previous_for_port "$port" "$countries_csv" "$selected_ip_path" "$map_path")"

  local cfbestip_added
  cfbestip_added="$(append_cfbestip_for_port "$port" "$countries_csv" "$selected_ip_path" "$map_path")"

  local vps789_added=0
  if [[ "$include_vps789" == "1" && -s "$VPS789_CT_IP_PATH" ]]; then
    while IFS= read -r ip; do
      [[ -n "$ip" ]] || continue
      if ! grep -Fxq "$ip" "$selected_ip_path"; then
        printf '%s\n' "$ip" >> "$selected_ip_path"
        vps789_added=$((vps789_added + 1))
      fi
      printf '%s,VPS789CT,vps789\n' "$ip" >> "$map_path"
    done < "$VPS789_CT_IP_PATH"
  fi

  local line_count
  line_count="$(grep -vcE '^[[:space:]]*(#|$)' "$selected_ip_path" || true)"
  if (( found == 0 || line_count == 0 )); then
    log "WARN: No usable country IP lines found for port $port."
    return 1
  fi

  log "Merged $line_count IP lines for port $port scope $scope into $selected_ip_path. previous added: $previous_added. cf-bestip added: $cfbestip_added. vps789 CT added: $vps789_added."
  printf '%s,%s,%s,%s\n' "$port" "$scope" "$selected_ip_path" "$map_path" >> "$WORK_DIR/port-work-items.csv"
}

start_cfst_for_port() {
  local port="$1"
  local scope="$2"
  local selected_ip_path="$3"
  local safe_scope="${scope//[^A-Za-z0-9_-]/_}"
  local csv_path="$WORK_DIR/CloudflareSpeedTest-$port-$safe_scope.csv"
  local stdout_path="$WORK_DIR/cfst-$port-$safe_scope-stdout.log"
  local stderr_path="$WORK_DIR/cfst-$port-$safe_scope-stderr.log"
  local args=(-f "$selected_ip_path" -o "$csv_path" -n "$CFST_THREADS" -t "$CFST_LATENCY_TEST_COUNT" -dn "$CFST_DOWNLOAD_TEST_COUNT" -dt "$CFST_DOWNLOAD_TEST_TIME" -tl "$MAX_LATENCY_MS" -tlr "$CFST_LOSS_RATE_LIMIT" -p 0)

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
  log "Starting cfst on port $port scope $scope: $CFST_PATH ${args[*]}"
  if [[ "$USE_PROXY_FOR_CFST" == "1" ]]; then
    (printf '\n' | "$CFST_PATH" "${args[@]}" > "$stdout_path" 2> "$stderr_path") &
  else
    (
      unset HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy https_proxy all_proxy no_proxy
      printf '\n' | "$CFST_PATH" "${args[@]}" > "$stdout_path" 2> "$stderr_path"
    ) &
  fi
  printf '%s,%s,%s,%s,%s\n' "$port" "$scope" "$!" "$csv_path" "$selected_ip_path" >> "$WORK_DIR/cfst-processes.csv"
}

wait_cfst_processes() {
  local failed=0
  while IFS=',' read -r port scope pid csv_path _selected_ip_path; do
    if ! wait "$pid"; then
      log "ERROR: cfst failed on port $port scope $scope."
      failed=1
    fi
    local safe_scope="${scope//[^A-Za-z0-9_-]/_}"
    [[ -f "$WORK_DIR/cfst-$port-$safe_scope-stdout.log" ]] && sed "s/^/cfst[$port/$scope]: /" "$WORK_DIR/cfst-$port-$safe_scope-stdout.log" | tee -a "$LOG_FILE" >/dev/null || true
    [[ -f "$WORK_DIR/cfst-$port-$safe_scope-stderr.log" ]] && sed "s/^/cfst[$port/$scope] stderr: /" "$WORK_DIR/cfst-$port-$safe_scope-stderr.log" | tee -a "$LOG_FILE" >/dev/null || true
    if [[ ! -f "$csv_path" ]]; then
      log "WARN: cfst completed but CSV was not created for port $port scope $scope: $csv_path"
    fi
  done < "$WORK_DIR/cfst-processes.csv"

  return "$failed"
}

build_combined_candidates() {
  : > "$COMBINED_CANDIDATES_PATH"
  while IFS=',' read -r port scope _selected_ip_path map_path; do
    local safe_scope="${scope//[^A-Za-z0-9_-]/_}"
    local csv_path="$WORK_DIR/CloudflareSpeedTest-$port-$safe_scope.csv"
    [[ -f "$csv_path" ]] || continue
    awk -F',' -v port="$port" '
      FNR == NR {
        if (NF >= 2) {
          mapped_source = (NF >= 3 && $3 != "") ? $3 : "unknown"
          if (!($1 in city_by_ip) || ((source_by_ip[$1] == "previous" || source_by_ip[$1] == "unknown") && mapped_source != "previous" && mapped_source != "unknown")) {
            city_by_ip[$1] = $2
            source_by_ip[$1] = mapped_source
          }
        }
        next
      }
      FNR == 1 { next }
      NF >= 6 {
        ip = $1
        city = city_by_ip[ip]
        datacenter = $7
        if (city == "VPS789CT") {
          if (datacenter != "" && datacenter != "N/A") {
            city = datacenter
          } else {
            city = "CT"
          }
        }
        source = source_by_ip[ip]
        if (source == "") source = "unknown"
        print port "," city "," source "," $0
      }
    ' "$map_path" "$csv_path" >> "$COMBINED_CANDIDATES_PATH"
  done < "$WORK_DIR/port-work-items.csv"
}

filter_csv() {
  local tmp_csv="$CSV_PATH.filtered"
  [[ -s "$PREVIOUS_NODE_KEYS_PATH" ]] || printf '__none__\n' > "$PREVIOUS_NODE_KEYS_PATH"
  if ! awk -F',' -v max_latency="$MAX_LATENCY_MS" -v min_received="$MIN_RECEIVED" -v min_speed_mbps="$MIN_SPEED_MBPS" -v max_per_city="$MAX_PER_CITY" -v test_location_name="$TEST_LOCATION_NAME" -v rolling_replace_fraction="$ROLLING_REPLACE_FRACTION" '
    FNR == NR {
      previous[$0] = 1
      next
    }
    {
      port = $1
      city = $2
      source = $3
      ip = $4
      sent = $5
      received = $6 + 0
      loss = $7 + 0
      latency = $8 + 0
      speed = $9 + 0
      datacenter = $10
      speed_mbps = speed * 8
      if (received >= min_received && loss < 1 && latency <= max_latency && speed_mbps >= min_speed_mbps) {
        remark = sprintf("%s [%.0fms %.2fMbps]", city, latency, speed_mbps)
        row = sprintf("%s,%s,%s,%s,true,%s,%s,%s,%s,%s,%s", ip, port, datacenter, remark, sent, received, loss, latency, speed, source)
        key = ip "|" port "|" city
        is_previous = (key in previous) ? 1 : 0
        dedupe_key = ip "|" port "|" city
        dedupe_row = sprintf("%s\t%012.6f\t%012.6f\t%d\t%s", city, 999999-speed, latency, is_previous, row)
        if (!(dedupe_key in best_row) || dedupe_row < best_row[dedupe_key]) {
          best_row[dedupe_key] = dedupe_row
        }
        kept++
      } else {
        removed++
      }
    }
    END {
      for (dedupe_key in best_row) rows[++count] = best_row[dedupe_key]
      if (count < 1) exit 2
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
      max_previous_keep = int(max_per_city * (1 - rolling_replace_fraction))
      for (i = 1; i <= count; i++) {
        split(rows[i], parts, "\t")
        city = parts[1]
        is_previous = parts[4] + 0
        if (city != current_city) {
          current_city = city
          city_count = 0
        }
        if (city_count < max_per_city && !(is_previous == 1 && previous_city_count[city] >= max_previous_keep)) {
          city_count++
          selected_total[city]++
          if (is_previous == 1) previous_city_count[city]++
          selected[++selected_count] = parts[5]
        } else if (is_previous == 1) {
          overflow_old[++overflow_count] = rows[i]
        }
      }
      for (i = 1; i <= overflow_count; i++) {
        split(overflow_old[i], parts, "\t")
        city = parts[1]
        if (selected_total[city] < max_per_city) {
          selected_total[city]++
          selected[++selected_count] = parts[5]
        }
      }
      for (i = 1; i <= selected_count; i++) {
          col_count = split(selected[i], cols, ",")
          city = cols[4]
          sub(/ .*/, "", city)
          sub(/\[.*/, "", city)
          output_city_count[city]++
          source = cols[col_count]
          if (source == "") source = "unknown"
          numbered_city = city "[" test_location_name sprintf("%02d", output_city_count[city]) " " source "]"
          cols[4] = numbered_city
          out = cols[1]
          for (k = 2; k < col_count; k++) {
            out = out "," cols[k]
          }
          print out
      }
    }
  ' "$PREVIOUS_NODE_KEYS_PATH" "$COMBINED_CANDIDATES_PATH" > "$tmp_csv"; then
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
  rm -f "$WORK_DIR/port-work-items.csv" "$WORK_DIR/cfst-processes.csv" "$COMBINED_CANDIDATES_PATH" "$CSV_PATH" "$VPS789_CT_IP_PATH" "$VPS789_CT_CSV_PATH" "$PREVIOUS_CSV_PATH" "$PREVIOUS_NODES_PATH" "$PREVIOUS_NODE_KEYS_PATH"

  update_zip_cache
  fetch_previous_csv_nodes
  fetch_vps789_ct_ips
  log "Extracting $ZIP_PATH"
  unzip -oq "$ZIP_PATH" -d "$EXTRACT_DIR"

  mapfile -t ports < <(effective_ports)
  log "Configured ports: ${ports[*]}"
  for port_value in "${ports[@]}"; do
    merge_country_files_for_port "$port_value" "all" "$COUNTRIES_CSV" "1" || true
    IFS=',' read -r -a focus_countries <<< "$FOCUS_COUNTRIES_CSV"
    for focus_country in "${focus_countries[@]}"; do
      focus_country="$(printf '%s' "$focus_country" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:lower:]' '[:upper:]')"
      [[ -n "$focus_country" ]] || continue
      merge_country_files_for_port "$port_value" "focus-$focus_country" "$focus_country" "0" || true
    done
  done

  if [[ ! -s "$WORK_DIR/port-work-items.csv" ]]; then
    log "ERROR: No usable port/country inputs were prepared."
    exit 1
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Dry run enabled. Skipping cfst execution and GitHub upload."
    while IFS=',' read -r port_value scope selected_ip_path _map_path; do
      safe_scope="${scope//[^A-Za-z0-9_-]/_}"
      args=(-f "$selected_ip_path" -o "$WORK_DIR/CloudflareSpeedTest-$port_value-$safe_scope.csv" -n "$CFST_THREADS" -t "$CFST_LATENCY_TEST_COUNT" -dn "$CFST_DOWNLOAD_TEST_COUNT" -dt "$CFST_DOWNLOAD_TEST_TIME" -tl "$MAX_LATENCY_MS" -tlr "$CFST_LOSS_RATE_LIMIT" -p 0)
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

  while IFS=',' read -r port_value scope selected_ip_path _map_path; do
    while (( $(jobs -rp | wc -l) >= MAX_PARALLEL_CFST )); do
      sleep 2
    done
    start_cfst_for_port "$port_value" "$scope" "$selected_ip_path"
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
