#!/usr/bin/env bash
set -euo pipefail

DOWNLOAD_URL="${DOWNLOAD_URL:-https://zip.cm.edu.kg/ip.zip}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK_DIR="${WORK_DIR:-$HOME/cfopt-auto-push}"
CFST_PATH="${CFST_PATH:-$WORK_DIR/cfst}"
PORT="${PORT:-}"
PORTS="${PORTS:-443,2053,2083,2087,2096,8443}"
DOWNLOAD_TEST_URL="${DOWNLOAD_TEST_URL:-https://cf.xiu2.xyz/url}"
COUNTRIES_CSV="${COUNTRIES_CSV:-HK,TW,JP,KR,SG,PH,VN,MY,KZ,MN,IE,US,DE,GB,NL,IT}"
OWNER="${OWNER:-GuardSkill}"
REPO="${REPO:-CFOpt}"
BRANCH="${BRANCH:-main}"
TARGET_PATH="${TARGET_PATH:-CloudflareSpeedTest_BJ.csv}"
INTERVAL_DAYS="${INTERVAL_DAYS:-}"
INTERVAL_HOURS="${INTERVAL_HOURS:-4}"
MAX_LATENCY_MS="${MAX_LATENCY_MS:-420}"
MIN_RECEIVED="${MIN_RECEIVED:-1}"
MIN_SPEED_MBPS="${MIN_SPEED_MBPS:-0.03}"
COUNTRY_MIN_SPEED_MB_PER_SEC="${COUNTRY_MIN_SPEED_MB_PER_SEC-JP=10,US=5,KR=3,HK=2,TW=3,DE=5,GB=3,SG=5}"
MAX_PER_CITY="${MAX_PER_CITY:-20}"
ROLLING_REPLACE_FRACTION="${ROLLING_REPLACE_FRACTION:-0.33}"
MIN_PUBLISH_RETENTION_RATIO="${MIN_PUBLISH_RETENTION_RATIO:-0.6}"
CFST_THREADS="${CFST_THREADS:-80}"
CFST_LATENCY_TEST_COUNT="${CFST_LATENCY_TEST_COUNT:-2}"
CFST_DOWNLOAD_TEST_COUNT="${CFST_DOWNLOAD_TEST_COUNT:-10}"
CFST_DOWNLOAD_TEST_TIME="${CFST_DOWNLOAD_TEST_TIME:-4}"
FOCUS_CFST_DOWNLOAD_TEST_COUNT="${FOCUS_CFST_DOWNLOAD_TEST_COUNT:-10}"
FOCUS_CFST_DOWNLOAD_TEST_TIME="${FOCUS_CFST_DOWNLOAD_TEST_TIME:-4}"
CFST_LOSS_RATE_LIMIT="${CFST_LOSS_RATE_LIMIT:-0}"
MAX_PARALLEL_CFST="${MAX_PARALLEL_CFST:-1}"
TCP_PRECHECK_ENABLED="${TCP_PRECHECK_ENABLED:-1}"
TCP_PRECHECK_MIN_CANDIDATES="${TCP_PRECHECK_MIN_CANDIDATES:-120}"
TCP_PRECHECK_TIMEOUT_MS="${TCP_PRECHECK_TIMEOUT_MS:-800}"
TCP_PRECHECK_THREADS="${TCP_PRECHECK_THREADS:-128}"
TCP_PRECHECK_MAX_CANDIDATES="${TCP_PRECHECK_MAX_CANDIDATES:-30}"
USE_PROXY_FOR_CFST="${USE_PROXY_FOR_CFST:-0}"
FOCUS_COUNTRIES_CSV="${FOCUS_COUNTRIES_CSV:-SG,HK,TW,JP,KR,US,DE,GB}"
TEST_LOCATION_NAME="${TEST_LOCATION_NAME:-}"
ENABLE_CFBESTIP="${ENABLE_CFBESTIP:-1}"
CFBESTIP_BASE_URL="${CFBESTIP_BASE_URL:-https://zoroaaa.github.io/cf-bestip}"
CFBESTIP_PER_COUNTRY_LIMIT="${CFBESTIP_PER_COUNTRY_LIMIT:-400}"
IPZIP_SAMPLE_ENABLED="${IPZIP_SAMPLE_ENABLED:-1}"
IPZIP_SAMPLE_PERCENT="${IPZIP_SAMPLE_PERCENT:-40}"
IPZIP_COUNTRY_MIN_CANDIDATES="${IPZIP_COUNTRY_MIN_CANDIDATES:-40}"
IPZIP_COUNTRY_MAX_CANDIDATES="${IPZIP_COUNTRY_MAX_CANDIDATES:-320}"
IPZIP_COUNTRY_SAMPLE_MULTIPLIERS="${IPZIP_COUNTRY_SAMPLE_MULTIPLIERS:-KR=2,US=0.5}"
ENABLE_VPS789_CT="${ENABLE_VPS789_CT:-0}"
VPS789_CT_LIMIT="${VPS789_CT_LIMIT:-100}"
VPS789_MAX_DX_LATENCY_MS="${VPS789_MAX_DX_LATENCY_MS:-260}"
VPS789_MAX_DX_LOSS_RATE="${VPS789_MAX_DX_LOSS_RATE:-5}"
TOKEN_ENV_NAME="${TOKEN_ENV_NAME:-GITHUB_TOKEN_CFOPT}"
FORCE="${FORCE:-0}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_UPLOAD="${SKIP_UPLOAD:-0}"
CFST_DEBUG="${CFST_DEBUG:-0}"
PROXYIP_BEST_SOURCE="${PROXYIP_BEST_SOURCE:-https://zip.cm.edu.kg/all.txt}"
PROXYIP_BEST_PATH="${PROXYIP_BEST_PATH:-$WORK_DIR/proxyip-best.txt}"
PROXYIP_BEST_TARGET_PATH="${PROXYIP_BEST_TARGET_PATH:-proxyip-best.txt}"
PROXYIP_BEST_COUNTRIES="${PROXYIP_BEST_COUNTRIES:-IE,AT,AU,KR,HK,TW,SG,JP,US,DE,GB}"
PROXYIP_BEST_LIMIT="${PROXYIP_BEST_LIMIT:-10}"
PROXYIP_BEST_COUNTRY_LIMITS="${PROXYIP_BEST_COUNTRY_LIMITS:-HK=50}"
PROXYIP_BEST_TIMEOUT="${PROXYIP_BEST_TIMEOUT:-0.75}"
PROXYIP_BEST_WORKERS="${PROXYIP_BEST_WORKERS:-64}"
PROXYIP_BEST_SCRIPT="${PROXYIP_BEST_SCRIPT:-$ROOT_DIR/scripts/generate_proxyip_best.py}"
DISABLE_PROXYIP_BEST="${DISABLE_PROXYIP_BEST:-0}"

ZIP_PATH="$WORK_DIR/ip.zip"
TMP_ZIP_PATH="$WORK_DIR/ip.download.zip"
EXTRACT_DIR="$WORK_DIR/extract"
CSV_PATH="$WORK_DIR/CloudflareSpeedTest.csv"
COMBINED_CANDIDATES_PATH="$WORK_DIR/CloudflareSpeedTest.candidates.csv"
PREVIOUS_CSV_PATH="$WORK_DIR/previous-CloudflareSpeedTest.csv"
PREVIOUS_NODES_PATH="$WORK_DIR/previous-nodes.csv"
PREVIOUS_NODE_KEYS_PATH="$WORK_DIR/previous-node-keys.txt"
COUNTRY_SPEED_STATS_PATH="$WORK_DIR/country-speed-floor-stats.csv"
VPS789_CT_IP_PATH="$WORK_DIR/vps789-ct-ip.txt"
VPS789_CT_CSV_PATH="$WORK_DIR/VPS789_CF_CT_Candidates.csv"
STATE_FILE="$WORK_DIR/last-success.txt"
LOG_FILE="$WORK_DIR/auto-push.log"

if [[ -z "$TEST_LOCATION_NAME" ]]; then
  TEST_LOCATION_NAME="BJ"
fi

log() {
  mkdir -p "$WORK_DIR"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

normalize_country_min_speed_map() {
  local value="$1"
  local allowed_countries="$2"

  awk -v value="$value" -v allowed_countries="$allowed_countries" '
    function trim(text) {
      sub(/^[[:space:]]+/, "", text)
      sub(/[[:space:]]+$/, "", text)
      return text
    }
    BEGIN {
      if (trim(value) == "") exit 0

      allowed_count = split(allowed_countries, allowed_parts, ",")
      for (i = 1; i <= allowed_count; i++) {
        country = toupper(trim(allowed_parts[i]))
        if (country != "") allowed[country] = 1
      }

      pair_count = split(value, pairs, ",")
      for (i = 1; i <= pair_count; i++) {
        pair = trim(pairs[i])
        field_count = split(pair, fields, "=")
        if (pair == "" || field_count != 2) exit 1

        country = toupper(trim(fields[1]))
        speed = trim(fields[2])
        if (country !~ /^[A-Z][A-Z]$/ || !(country in allowed)) exit 1
        if (speed !~ /^([0-9]+(\.[0-9]+)?|\.[0-9]+)$/) exit 1
        if ((speed + 0) > 1.7976931348623157e308) exit 1
        if (country in seen) exit 1

        seen[country] = 1
        normalized[++normalized_count] = country "=" speed
      }

      for (i = 1; i <= normalized_count; i++) {
        printf "%s%s", (i == 1 ? "" : ","), normalized[i]
      }
    }
  '
}

COUNTRY_MIN_SPEED_MB_PER_SEC_NORMALIZED="$(normalize_country_min_speed_map "$COUNTRY_MIN_SPEED_MB_PER_SEC" "$COUNTRIES_CSV")" || {
  log "ERROR: Invalid COUNTRY_MIN_SPEED_MB_PER_SEC: $COUNTRY_MIN_SPEED_MB_PER_SEC"
  exit 1
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

  local interval_hours="$INTERVAL_HOURS"
  if [[ -n "$INTERVAL_DAYS" && "${INTERVAL_HOURS:-}" == "4" ]]; then
    interval_hours=$((INTERVAL_DAYS * 24))
  fi

  local last_epoch now_epoch next_epoch
  last_epoch="$(date -d "$(cat "$STATE_FILE")" +%s 2>/dev/null || echo 0)"
  now_epoch="$(date +%s)"
  next_epoch=$((last_epoch + interval_hours * 3600))

  if (( now_epoch < next_epoch )); then
    log "Skipped. Last successful run has not reached ${interval_hours} hours."
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
city_re = re.compile(r"\b([A-Za-z]{2})\b")
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
        match = city_re.search(city_text)
        if not match:
            continue
        city = match.group(1).upper()
        if re.match(r"^(?:\d{1,3}\.){3}\d{1,3}$", ip) and port.isdigit():
            rows.append((ip, port, city))

with open(nodes_path, "w", encoding="ascii", newline="") as f:
    writer = csv.writer(f, lineterminator="\n")
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
      added=$((added + 1))
    fi
    printf '%s,%s,previous\n' "$ip" "$city" >> "$map_path"
  done < "$PREVIOUS_NODES_PATH"

  printf '%s\n' "$added"
}

focus_excluded_countries_csv() {
  local countries_csv="$1"
  local focus_countries_csv="$2"

  awk -v countries="$countries_csv" -v focus="$focus_countries_csv" '
    BEGIN {
      split(focus, focus_items, ",")
      for (i in focus_items) {
        country = toupper(focus_items[i])
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", country)
        if (country != "") focus_set[country] = 1
      }

      split(countries, country_items, ",")
      for (i = 1; i <= length(country_items); i++) {
        country = toupper(country_items[i])
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", country)
        if (country != "" && !(country in focus_set)) {
          printf "%s%s", sep, country
          sep = ","
        }
      }
    }
  '
}

append_ipzip_country_file() {
  local country="$1"
  local file="$2"
  local selected_ip_path="$3"
  local map_path="$4"
  local sampled_path
  sampled_path="$(mktemp)"

  awk \
    -v enabled="$IPZIP_SAMPLE_ENABLED" \
    -v percent="$IPZIP_SAMPLE_PERCENT" \
    -v min_keep="$IPZIP_COUNTRY_MIN_CANDIDATES" \
    -v max_keep="$IPZIP_COUNTRY_MAX_CANDIDATES" \
    -v country="$country" \
    -v multipliers="$IPZIP_COUNTRY_SAMPLE_MULTIPLIERS" '
      function country_multiplier(   i, parts, key, value, nitems, items) {
        nitems = split(multipliers, items, /[,[:space:]]+/)
        for (i = 1; i <= nitems; i++) {
          if (items[i] == "") continue
          split(items[i], parts, "=")
          key = toupper(parts[1])
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
          value = parts[2] + 0
          if (key == toupper(country) && value > 0) return value
        }
        return 1
      }
      /^[[:space:]]*(#|$)/ { next }
      {
        line = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line != "") rows[++n] = line
      }
      END {
        if (n == 0) exit
        if (enabled != "1") {
          for (i = 1; i <= n; i++) print rows[i]
          exit
        }

        pct = percent + 0
        multiplier = country_multiplier()
        min_count = int((min_keep + 0) * multiplier)
        max_count = int((max_keep + 0) * multiplier)
        if (pct <= 0 || pct > 100) pct = 100
        pct = pct * multiplier
        if (pct > 100) pct = 100
        if (min_count < 0) min_count = 0

        target = int((n * pct + 99) / 100)
        if (target < min_count) target = min_count
        if (max_count > 0 && target > max_count) target = max_count
        if (target > n) target = n

        if (target >= n) {
          for (i = 1; i <= n; i++) print rows[i]
          exit
        }

        step = n / target
        for (i = 1; i <= target; i++) {
          idx = int((i - 1) * step) + 1
          if (idx > n) idx = n
          if (!(idx in picked)) {
            print rows[idx]
            picked[idx] = 1
          }
        }
      }
    ' "$file" > "$sampled_path"

  cat "$sampled_path" >> "$selected_ip_path"
  awk -v city="$country" 'NF { print $0 "," city ",ip.zip" }' "$sampled_path" >> "$map_path"
  rm -f "$sampled_path"
}

merge_country_files_for_port() {
  local port="$1"
  local scope="${2:-all}"
  local countries_csv="${3:-$COUNTRIES_CSV}"
  local include_vps789="${4:-1}"
  local include_previous="${5:-1}"
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
    append_ipzip_country_file "$country" "$file" "$selected_ip_path" "$map_path"
    found=$((found + 1))
  done

  local previous_added=0
  if [[ "$include_previous" == "1" ]]; then
    previous_added="$(append_previous_for_port "$port" "$countries_csv" "$selected_ip_path" "$map_path")"
  fi

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

prepare_previous_work_item() {
  local port="$1" safe_scope="previous"
  local selected_ip_path="$WORK_DIR/selected-ip-$port-$safe_scope.txt"
  local map_path="$WORK_DIR/selected-ip-city-map-$port-$safe_scope.csv"
  [[ -s "$PREVIOUS_NODES_PATH" ]] || return 0
  : > "$selected_ip_path"
  : > "$map_path"
  awk -F',' -v port="$port" -v ips="$selected_ip_path" -v map="$map_path" '
    $2 == port && $1 != "" && $3 != "" {
      if (!seen[$1]++) print $1 >> ips
      print $1 "," $3 ",previous" >> map
    }
  ' "$PREVIOUS_NODES_PATH"
  local count
  count="$(grep -vcE '^[[:space:]]*(#|$)' "$selected_ip_path" || true)"
  (( count > 0 )) || return 0
  log "Prepared $count previous nodes for full download retest on port $port."
  printf '%s,%s,%s,%s\n' "$port" "$safe_scope" "$selected_ip_path" "$map_path" >> "$WORK_DIR/port-work-items.csv"
}

positive_tcp_precheck_value() {
  local value="$1"
  local fallback="$2"
  if [[ "$value" =~ ^[0-9]+$ ]] && (( value > 0 )); then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$fallback"
  fi
}

apply_tcp_precheck() {
  local port="$1"
  local selected_ip_path="$2"
  local map_path="$3"
  local input_count start_ms elapsed_ms timeout_seconds tmp_dir
  local new_map_path previous_path results_path errors_path kept_new_path output_path
  local kept_previous connected kept_new ip probe_start probe_elapsed probe_pid probe_status
  local effective_timeout_ms effective_threads effective_max_candidates
  local -a probe_pids=()

  input_count="$(grep -vcE '^[[:space:]]*(#|$)' "$selected_ip_path" || true)"
  if [[ "$TCP_PRECHECK_ENABLED" != "1" || "$input_count" -le "$TCP_PRECHECK_MIN_CANDIDATES" ]]; then
    return 0
  fi
  effective_timeout_ms="$(positive_tcp_precheck_value "$TCP_PRECHECK_TIMEOUT_MS" 800)"
  effective_threads="$(positive_tcp_precheck_value "$TCP_PRECHECK_THREADS" 128)"
  effective_max_candidates="$(positive_tcp_precheck_value "$TCP_PRECHECK_MAX_CANDIDATES" 30)"

  start_ms="$(date +%s%3N)"
  tmp_dir="$(mktemp -d "$WORK_DIR/tcp-precheck.XXXXXX")" || {
    log "WARN: TCP precheck failed; using original candidates."
    return 0
  }
  new_map_path="$tmp_dir/new.csv"
  previous_path="$tmp_dir/previous.txt"
  results_path="$tmp_dir/results.tsv"
  errors_path="$tmp_dir/errors.txt"
  kept_new_path="$tmp_dir/kept-new.txt"
  output_path="$tmp_dir/selected.txt"
  : > "$new_map_path"
  : > "$previous_path"
  : > "$results_path"
  : > "$errors_path"

  if ! awk -F',' -v new_map="$new_map_path" -v previous="$previous_path" '
    NR == FNR {
      if (!($1 in city) || $3 == "previous" || (source[$1] == "unknown" && $3 != "unknown")) {
        city[$1] = $2
        source[$1] = $3
      }
      next
    }
    /^[[:space:]]*(#|$)/ { next }
    {
      ip = $1
      if (source[ip] == "previous") print ip >> previous
      else {
        ordinal++
        print ip "," city[ip] "," source[ip] "," ordinal >> new_map
      }
    }
  ' "$map_path" "$selected_ip_path"; then
    log "WARN: TCP precheck failed; using original candidates."
    rm -rf "$tmp_dir"
    return 0
  fi

  timeout_seconds="$(awk -v milliseconds="$effective_timeout_ms" 'BEGIN { printf "%.3f", milliseconds / 1000 }')"
  while IFS=',' read -r ip _city _source ordinal; do
    [[ -n "$ip" ]] || continue
    (
      probe_start="$(date +%s%3N)"
      probe_status=0
      timeout "$timeout_seconds" bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$ip" "$port" 2>/dev/null || probe_status=$?
      if (( probe_status == 0 )); then
        probe_elapsed=$(( $(date +%s%3N) - probe_start ))
        printf '%s\t%s\t%s\n' "$ip" "$probe_elapsed" "$ordinal" >> "$results_path"
      elif (( probe_status == 125 || probe_status == 126 || probe_status == 127 )); then
        printf '%s\n' "$probe_status" >> "$errors_path"
      fi
    ) &
    probe_pids+=("$!")
    if (( ${#probe_pids[@]} >= effective_threads )); then
      wait "${probe_pids[0]}" || true
      probe_pids=("${probe_pids[@]:1}")
    fi
  done < "$new_map_path"
  for probe_pid in "${probe_pids[@]}"; do
    wait "$probe_pid" || true
  done

  if [[ -s "$errors_path" ]]; then
    log "WARN: TCP precheck failed; using original candidates."
    rm -rf "$tmp_dir"
    return 0
  fi

  if ! sort -s -t $'\t' -k2,2n -k3,3n "$results_path" | awk -F'\t' -v map_path="$new_map_path" -v max_keep="$effective_max_candidates" '
    BEGIN {
      while ((getline line < map_path) > 0) {
        split(line, fields, ",")
        group_by_ip[fields[1]] = fields[2] SUBSEP fields[3]
      }
      close(map_path)
    }
    {
      group = group_by_ip[$1]
      if (++kept[group] <= max_keep) print $1
    }
  ' > "$kept_new_path"; then
    log "WARN: TCP precheck failed; using original candidates."
    rm -rf "$tmp_dir"
    return 0
  fi

  {
    cat "$kept_new_path"
    cat "$previous_path"
  } | awk 'NF && !seen[$0]++' > "$output_path"

  kept_previous="$(grep -vcE '^[[:space:]]*(#|$)' "$previous_path" || true)"
  connected="$(grep -vcE '^[[:space:]]*(#|$)' "$results_path" || true)"
  kept_new="$(grep -vcE '^[[:space:]]*(#|$)' "$kept_new_path" || true)"
  if (( kept_new + kept_previous == 0 )); then
    log "WARN: TCP precheck found no usable candidates for port $port."
    : > "$selected_ip_path"
  else
    mv "$output_path" "$selected_ip_path"
  fi
  elapsed_ms=$(( $(date +%s%3N) - start_ms ))
  log "TCP precheck input=$input_count connected=$connected kept_new=$kept_new kept_previous=$kept_previous elapsed_ms=$elapsed_ms port=$port"
  rm -rf "$tmp_dir"
}

prune_empty_work_items() {
  local work_items_path="$1"
  local filtered_path="$work_items_path.tcp-precheck"
  local port scope selected_ip_path map_path
  : > "$filtered_path"
  while IFS=',' read -r port scope selected_ip_path map_path; do
    if [[ -s "$selected_ip_path" ]]; then
      printf '%s,%s,%s,%s\n' "$port" "$scope" "$selected_ip_path" "$map_path" >> "$filtered_path"
    else
      log "WARN: Skipping empty TCP precheck work item port=$port scope=$scope."
    fi
  done < "$work_items_path"
  mv "$filtered_path" "$work_items_path"
}

start_cfst_for_port() {
  local port="$1"
  local scope="$2"
  local selected_ip_path="$3"
  local safe_scope="${scope//[^A-Za-z0-9_-]/_}"
  local csv_path="$WORK_DIR/CloudflareSpeedTest-$port-$safe_scope.csv"
  local stdout_path="$WORK_DIR/cfst-$port-$safe_scope-stdout.log"
  local stderr_path="$WORK_DIR/cfst-$port-$safe_scope-stderr.log"
  local download_test_count="$CFST_DOWNLOAD_TEST_COUNT"
  local download_test_time="$CFST_DOWNLOAD_TEST_TIME"
  if [[ "$scope" == focus-* ]]; then
    download_test_count="$FOCUS_CFST_DOWNLOAD_TEST_COUNT"
    download_test_time="$FOCUS_CFST_DOWNLOAD_TEST_TIME"
  fi
  if [[ "$scope" == "previous" ]]; then
    download_test_count="$(grep -vcE '^[[:space:]]*(#|$)' "$selected_ip_path" || true)"
  fi
  local args=(-f "$selected_ip_path" -o "$csv_path" -n "$CFST_THREADS" -t "$CFST_LATENCY_TEST_COUNT" -dn "$download_test_count" -dt "$download_test_time" -tl "$MAX_LATENCY_MS" -tlr "$CFST_LOSS_RATE_LIMIT" -p 0)

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
  LAST_CFST_RECORD="$port,$scope,$!,$csv_path,$selected_ip_path"
}

wait_cfst_record() {
  local record="$1"
  local failed=0
  local port scope pid csv_path _selected_ip_path
  IFS=',' read -r port scope pid csv_path _selected_ip_path <<< "$record"

  if ! wait "$pid"; then
    log "ERROR: cfst failed on port $port scope $scope."
    failed=1
  fi
  local safe_scope="${scope//[^A-Za-z0-9_-]/_}"
  [[ -f "$WORK_DIR/cfst-$port-$safe_scope-stdout.log" ]] && awk -v prefix="cfst[$port/$scope]: " '{ print prefix $0 }' "$WORK_DIR/cfst-$port-$safe_scope-stdout.log" | tee -a "$LOG_FILE" >/dev/null || true
  [[ -f "$WORK_DIR/cfst-$port-$safe_scope-stderr.log" ]] && awk -v prefix="cfst[$port/$scope] stderr: " '{ print prefix $0 }' "$WORK_DIR/cfst-$port-$safe_scope-stderr.log" | tee -a "$LOG_FILE" >/dev/null || true
  if [[ ! -f "$csv_path" ]]; then
    log "WARN: cfst completed but CSV was not created for port $port scope $scope: $csv_path"
  fi
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
  local tmp_csv="$CSV_PATH.filtered" filter_status=0
  rm -f "$COUNTRY_SPEED_STATS_PATH"
  [[ -s "$PREVIOUS_NODE_KEYS_PATH" ]] || printf '__none__\n' > "$PREVIOUS_NODE_KEYS_PATH"
  awk -F',' -v max_latency="$MAX_LATENCY_MS" -v min_received="$MIN_RECEIVED" -v min_speed_mbps="$MIN_SPEED_MBPS" -v max_per_city="$MAX_PER_CITY" -v test_location_name="$TEST_LOCATION_NAME" -v rolling_replace_fraction="$ROLLING_REPLACE_FRACTION" -v country_speed_floors="$COUNTRY_MIN_SPEED_MB_PER_SEC_NORMALIZED" -v country_speed_stats_path="$COUNTRY_SPEED_STATS_PATH" '
    BEGIN {
      floor_count = split(country_speed_floors, floor_entries, ",")
      for (i = 1; i <= floor_count; i++) {
        split(floor_entries[i], floor_parts, "=")
        country_floor[floor_parts[1]] = floor_parts[2] + 0
        country_floor_value[floor_parts[1]] = floor_parts[2]
        country_floor_codes[++country_floor_code_count] = floor_parts[1]
      }
    }
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
      speed_text = $9
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", speed_text)
      if (speed_text !~ /^([0-9]+(\.[0-9]+)?|\.[0-9]+)$/) {
        removed++
        next
      }
      speed = speed_text + 0
      if (speed > 1.7976931348623157e308) {
        removed++
        next
      }
      datacenter = $10
      speed_mbps = speed * 8
      if (received >= min_received && loss < 1 && latency <= max_latency && speed_mbps >= min_speed_mbps) {
        remark = sprintf("%s [%.0fms %.2fMbps]", city, latency, speed_mbps)
        row = sprintf("%s,%s,%s,%s,true,%s,%s,%s,%s,%s,%s", ip, port, datacenter, remark, sent, received, loss, latency, speed, source)
        key = ip "|" port "|" city
        is_previous = (key in previous) ? 1 : 0
        dedupe_key = ip "|" city
        if (!(dedupe_key in best_row) || speed > best_speed[dedupe_key] || (speed == best_speed[dedupe_key] && latency < best_latency[dedupe_key])) {
          best_row[dedupe_key] = row
          best_city[dedupe_key] = city
          best_speed[dedupe_key] = speed
          best_latency[dedupe_key] = latency
          best_previous[dedupe_key] = is_previous
        }
        kept++
      } else {
        removed++
      }
    }
    END {
      for (dedupe_key in best_row) {
        rows[++count] = sprintf("%s\t%020.6f\t%020.6f\t%d\t%s", best_city[dedupe_key], 999999999-best_speed[dedupe_key], best_latency[dedupe_key], best_previous[dedupe_key], best_row[dedupe_key])
      }
      for (i = 1; i <= count; i++) {
        for (j = i + 1; j <= count; j++) {
          if (rows[j] < rows[i]) {
            tmp = rows[i]; rows[i] = rows[j]; rows[j] = tmp
          }
        }
      }
      for (i = 1; i <= count; i++) {
        split(rows[i], parts, "\t")
        city = parts[1]
        speed = 999999999 - (parts[2] + 0)
        country_rank[city]++
        protected = 0
        if (city in country_floor) {
          country_evaluated[city]++
          if (speed < country_floor[city]) {
            country_removed[city]++
            removed++
            continue
          } else {
            country_passed[city]++
          }
        }
        accepted[++accepted_count] = sprintf("%s\t%020.6f\t%020.6f\t%d\t%d\t%s", city, parts[3] + 0, parts[2] + 0, parts[4] + 0, protected, parts[5])
      }
      for (i = 1; i <= country_floor_code_count; i++) {
        country = country_floor_codes[i]
        print country "," country_floor_value[country] "," (country_evaluated[country] + 0) "," (country_protected[country] + 0) "," (country_removed[country] + 0) "," (country_passed[country] + 0) > country_speed_stats_path
      }
      if (accepted_count < 1) exit 2
      print "IP地址,端口,数据中心,城市,TLS,已发送,已接收,丢包率,平均延迟,下载速度(MB/s)"
      for (i = 1; i <= accepted_count; i++) {
        for (j = i + 1; j <= accepted_count; j++) {
          if (accepted[j] < accepted[i]) {
            tmp = accepted[i]; accepted[i] = accepted[j]; accepted[j] = tmp
          }
        }
      }
      max_previous_keep = int(max_per_city * (1 - rolling_replace_fraction))
      for (i = 1; i <= accepted_count; i++) {
        split(accepted[i], parts, "\t")
        city = parts[1]
        is_previous = parts[4] + 0
        protected = parts[5] + 0
        if (protected == 1 && selected_total[city] < max_per_city) {
          selected_total[city]++
          if (is_previous == 1) previous_city_count[city]++
          selected[++selected_count] = parts[6]
        }
      }
      for (i = 1; i <= accepted_count; i++) {
        split(accepted[i], parts, "\t")
        city = parts[1]
        is_previous = parts[4] + 0
        protected = parts[5] + 0
        if (protected == 1) continue
        if (selected_total[city] < max_per_city && !(is_previous == 1 && previous_city_count[city] >= max_previous_keep)) {
          selected_total[city]++
          if (is_previous == 1) previous_city_count[city]++
          selected[++selected_count] = parts[6]
        } else if (is_previous == 1) {
          overflow_old[++overflow_count] = accepted[i]
        }
      }
      for (i = 1; i <= overflow_count; i++) {
        split(overflow_old[i], parts, "\t")
        city = parts[1]
        if (selected_total[city] < max_per_city) {
          selected_total[city]++
          selected[++selected_count] = parts[6]
        }
      }
      for (i = 1; i <= selected_count; i++) {
          col_count = split(selected[i], cols, ",")
          city = cols[4]
          sub(/ .*/, "", city)
          sub(/\[.*/, "", city)
          output_city_count[city]++
          speed_label = sprintf("%.1fMB/s", cols[col_count-1] + 0)
          numbered_city = city " [" test_location_name "#" sprintf("%02d", output_city_count[city]) " " speed_label "]"
          cols[4] = numbered_city
          out = cols[1]
          for (k = 2; k < col_count; k++) {
            out = out "," cols[k]
          }
          print out
      }
    }

    function country_flag(code) {
      code = toupper(code)
      if (code == "AT") return "🇦🇹"
      if (code == "AU") return "🇦🇺"
      if (code == "CT") return "🇨🇳"
      if (code == "DE") return "🇩🇪"
      if (code == "GB") return "🇬🇧"
      if (code == "HK") return "🇭🇰"
      if (code == "IE") return "🇮🇪"
      if (code == "IT") return "🇮🇹"
      if (code == "JP") return "🇯🇵"
      if (code == "KR") return "🇰🇷"
      if (code == "KZ") return "🇰🇿"
      if (code == "MN") return "🇲🇳"
      if (code == "MY") return "🇲🇾"
      if (code == "NL") return "🇳🇱"
      if (code == "PH") return "🇵🇭"
      if (code == "SG") return "🇸🇬"
      if (code == "US") return "🇺🇸"
      if (code == "VN") return "🇻🇳"
      return ""
    }
  ' "$PREVIOUS_NODE_KEYS_PATH" "$COMBINED_CANDIDATES_PATH" > "$tmp_csv" || filter_status=$?
  if [[ -f "$COUNTRY_SPEED_STATS_PATH" ]]; then
    local country floor evaluated protected removed passed
    while IFS=',' read -r country floor evaluated protected removed passed; do
      [[ -n "$country" ]] || continue
      log "Country speed floor $country >= $floor MB/s: evaluated=$evaluated protected=$protected removed=$removed passed=$passed."
    done < "$COUNTRY_SPEED_STATS_PATH"
  fi
  if ((filter_status != 0)); then
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

publish_file_to_github() {
  local local_path="$1"
  local target_path="$2"
  local message="$3"
  local token="${!TOKEN_ENV_NAME:-}"
  if [[ -z "$token" ]]; then
    log "ERROR: Missing GitHub token. Set $TOKEN_ENV_NAME."
    return 1
  fi

  local encoded_path
  encoded_path="$(python3 - "$target_path" <<'PY'
import sys, urllib.parse
print("/".join(urllib.parse.quote(part, safe="") for part in sys.argv[1].split("/")))
PY
)"
  local uri="https://api.github.com/repos/$OWNER/$REPO/contents/$encoded_path"
  local meta_file="$WORK_DIR/github-meta.json"
  local status
  status="$(curl -sS --retry 3 --retry-connrefused -o "$meta_file" -w '%{http_code}' \
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

  local content body_file response_file put_status
  content="$(base64 -w 0 "$local_path")"
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

  put_status="$(curl -sS --retry 3 --retry-connrefused -o "$response_file" -w '%{http_code}' -X PUT \
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

  log "Uploaded $local_path to $OWNER/$REPO/$target_path."
}

publish_to_github() {
  publish_file_to_github "$CSV_PATH" "$TARGET_PATH" "Update $TARGET_PATH"
}

assert_publication_safety() {
  [[ -s "$PREVIOUS_NODES_PATH" ]] || return 0
  if ! awk -F',' -v ratio="$MIN_PUBLISH_RETENTION_RATIO" '
    FILENAME == ARGV[1] { previous[$3]++; previous_total++; next }
    FNR == 1 { next }
    { city=substr($4, 1, 2); current[city]++; current_total++ }
    END {
      required_total = int(previous_total * ratio + 0.999999)
      if (current_total < required_total) {
        printf "Publication safety check blocked upload: current rows %d are below %d required from %d previous rows.\n", current_total, required_total, previous_total > "/dev/stderr"
        exit 1
      }
      for (city in previous) {
        required = int(previous[city] * ratio + 0.999999)
        if ((current[city] + 0) < required) {
          printf "Publication safety check blocked upload: %s has %d rows, below %d required from %d previous rows.\n", city, current[city] + 0, required, previous[city] > "/dev/stderr"
          exit 1
        }
      }
    }
  ' "$PREVIOUS_NODES_PATH" "$CSV_PATH"; then
    return 1
  fi
  log "Publication safety check passed: retention_ratio=$MIN_PUBLISH_RETENTION_RATIO."
}

generate_proxyip_best() {
  if [[ "$DISABLE_PROXYIP_BEST" == "1" ]]; then
    log "proxyip-best generation disabled."
    return 0
  fi
  if [[ ! -f "$PROXYIP_BEST_SCRIPT" ]]; then
    log "WARN: proxyip-best script not found: $PROXYIP_BEST_SCRIPT"
    return 0
  fi
  log "Generating proxyip best list from $PROXYIP_BEST_SOURCE"
  if ! python3 "$PROXYIP_BEST_SCRIPT" \
    --source "$PROXYIP_BEST_SOURCE" \
    --output "$PROXYIP_BEST_PATH" \
    --countries "$PROXYIP_BEST_COUNTRIES" \
    --limit "$PROXYIP_BEST_LIMIT" \
    --country-limits "$PROXYIP_BEST_COUNTRY_LIMITS" \
    --timeout "$PROXYIP_BEST_TIMEOUT" \
    --workers "$PROXYIP_BEST_WORKERS"; then
    log "WARN: proxyip-best generation failed."
    return 0
  fi
  log "Generated proxyip best list: $PROXYIP_BEST_PATH"
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
  all_countries_csv="$(focus_excluded_countries_csv "$COUNTRIES_CSV" "$FOCUS_COUNTRIES_CSV")"
  for port_value in "${ports[@]}"; do
    prepare_previous_work_item "$port_value"
    if [[ -n "$all_countries_csv" ]]; then
      merge_country_files_for_port "$port_value" "all" "$all_countries_csv" "1" "0" || true
    fi
    IFS=',' read -r -a focus_countries <<< "$FOCUS_COUNTRIES_CSV"
    for focus_country in "${focus_countries[@]}"; do
      focus_country="$(printf '%s' "$focus_country" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:lower:]' '[:upper:]')"
      [[ -n "$focus_country" ]] || continue
      merge_country_files_for_port "$port_value" "focus-$focus_country" "$focus_country" "0" "0" || true
    done
  done

  if [[ ! -s "$WORK_DIR/port-work-items.csv" ]]; then
    log "ERROR: No usable port/country inputs were prepared."
    exit 1
  fi

  while IFS=',' read -r port_value _scope selected_ip_path map_path; do
    apply_tcp_precheck "$port_value" "$selected_ip_path" "$map_path"
  done < "$WORK_DIR/port-work-items.csv"
  prune_empty_work_items "$WORK_DIR/port-work-items.csv"
  if [[ ! -s "$WORK_DIR/port-work-items.csv" ]]; then
    log "ERROR: No usable port/country inputs remained after TCP precheck."
    exit 1
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Dry run enabled. Skipping cfst execution and GitHub upload."
    while IFS=',' read -r port_value scope selected_ip_path _map_path; do
      safe_scope="${scope//[^A-Za-z0-9_-]/_}"
      download_test_count="$CFST_DOWNLOAD_TEST_COUNT"
      download_test_time="$CFST_DOWNLOAD_TEST_TIME"
      if [[ "$scope" == focus-* ]]; then
        download_test_count="$FOCUS_CFST_DOWNLOAD_TEST_COUNT"
        download_test_time="$FOCUS_CFST_DOWNLOAD_TEST_TIME"
      fi
      args=(-f "$selected_ip_path" -o "$WORK_DIR/CloudflareSpeedTest-$port_value-$safe_scope.csv" -n "$CFST_THREADS" -t "$CFST_LATENCY_TEST_COUNT" -dn "$download_test_count" -dt "$download_test_time" -tl "$MAX_LATENCY_MS" -tlr "$CFST_LOSS_RATE_LIMIT" -p 0)
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

  local max_parallel="$MAX_PARALLEL_CFST"
  if (( max_parallel < 1 )); then
    max_parallel=1
  fi
  local cfst_failed=0
  local -a active_cfst_records=()
  while IFS=',' read -r port_value scope selected_ip_path _map_path; do
    while (( ${#active_cfst_records[@]} >= max_parallel )); do
      if ! wait_cfst_record "${active_cfst_records[0]}"; then
        cfst_failed=1
      fi
      active_cfst_records=("${active_cfst_records[@]:1}")
    done
    start_cfst_for_port "$port_value" "$scope" "$selected_ip_path"
    active_cfst_records+=("$LAST_CFST_RECORD")
  done < "$WORK_DIR/port-work-items.csv"

  for cfst_record in "${active_cfst_records[@]}"; do
    if ! wait_cfst_record "$cfst_record"; then
      cfst_failed=1
    fi
  done
  if (( cfst_failed != 0 )); then
    exit 1
  fi
  build_combined_candidates
  filter_csv
  assert_publication_safety

  if [[ "$SKIP_UPLOAD" == "1" ]]; then
    log "SkipUpload enabled. CSV generated but GitHub upload and success-state update were skipped."
    exit 0
  fi

  publish_to_github
  generate_proxyip_best
  if [[ -s "$PROXYIP_BEST_PATH" ]]; then
    publish_file_to_github "$PROXYIP_BEST_PATH" "$PROXYIP_BEST_TARGET_PATH" "Update $PROXYIP_BEST_TARGET_PATH"
  fi
  date --iso-8601=seconds > "$STATE_FILE"
  log "Completed successfully."
}

if [[ "${CFOPT_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
