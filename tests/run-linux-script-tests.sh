#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_cfst_log_prefix_handles_scopes() {
  local tmp_dir zip_src zip_path stub_cfst stdout_path stderr_path
  tmp_dir="$(mktemp -d)"
  zip_src="$tmp_dir/zip-src"
  zip_path="$tmp_dir/ip.zip"
  stub_cfst="$tmp_dir/cfst"
  stdout_path="$tmp_dir/script.stdout"
  stderr_path="$tmp_dir/script.stderr"

  mkdir -p "$zip_src/443"
  printf '104.16.132.229\n' > "$zip_src/443/HK.txt"
  (cd "$zip_src" && zip -qr "$zip_path" .)

  cat > "$stub_cfst" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out=""
while (($#)); do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf 'stub stdout\n'
printf 'stub stderr\n' >&2
{
  printf 'IP 地址,已发送,已接收,丢包率,平均延迟,下载速度(MB/s),地区码\n'
  printf '104.16.132.229,1,1,0.00,100.00,1.00,HKG\n'
} > "$out"
SH
  chmod +x "$stub_cfst"

  FORCE=1 \
  SKIP_UPLOAD=1 \
  ENABLE_CFBESTIP=0 \
  DOWNLOAD_URL="file://$zip_path" \
  WORK_DIR="$tmp_dir/work" \
  CFST_PATH="$stub_cfst" \
  PORTS=443 \
  COUNTRIES_CSV=HK \
  FOCUS_COUNTRIES_CSV=HK \
  CFST_THREADS=1 \
  CFST_LATENCY_TEST_COUNT=1 \
  CFST_DOWNLOAD_TEST_COUNT=1 \
  CFST_DOWNLOAD_TEST_TIME=1 \
  MIN_SPEED_MBPS=0 \
  bash "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" >"$stdout_path" 2>"$stderr_path"

  if grep -q 'sed: .*unknown option to `s'\''\|unknown option to .s.' "$stderr_path"; then
    fail "cfst log prefix emitted a sed expression error"
  fi
  grep -q 'cfst\[443/focus-HK\]: stub stdout' "$tmp_dir/work/auto-push.log" || fail "prefixed stdout log was not captured"
  grep -q 'cfst\[443/focus-HK\] stderr: stub stderr' "$tmp_dir/work/auto-push.log" || fail "prefixed stderr log was not captured"
  grep -q 'HK \[BJ#01 ip.zip\]' "$tmp_dir/work/CloudflareSpeedTest.csv" || fail "generated CSV city should use ASCII labels"
}

test_linux_defaults_are_not_overly_strict_for_local_runs() {
  if grep -q 'MIN_SPEED_MBPS:-0\.01' "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh"; then
    fail "Linux runner default MIN_SPEED_MBPS should not require a nonzero speed floor"
  fi
  if grep -q 'DOWNLOAD_TEST_URL:-https://speed.cloudflare.com/__down?bytes=100000000' "$ROOT_DIR/scripts/linux/install-and-run-cfopt-linux.sh"; then
    fail "installer should not override the runner download-test URL by default"
  fi
}

test_linux_runner_samples_large_country_files() {
  local tmp_dir zip_src zip_path stdout_path stderr_path
  tmp_dir="$(mktemp -d)"
  zip_src="$tmp_dir/zip-src"
  zip_path="$tmp_dir/ip.zip"
  stdout_path="$tmp_dir/script.stdout"
  stderr_path="$tmp_dir/script.stderr"

  mkdir -p "$zip_src/443"
  for i in $(seq 1 100); do
    printf '198.18.0.%s\n' "$i"
  done > "$zip_src/443/DE.txt"
  (cd "$zip_src" && zip -qr "$zip_path" .)

  FORCE=1 \
  DRY_RUN=1 \
  ENABLE_CFBESTIP=0 \
  DOWNLOAD_URL="file://$zip_path" \
  WORK_DIR="$tmp_dir/work" \
  CFST_PATH="$tmp_dir/missing-cfst-ok-for-dry-run" \
  PORTS=443 \
  COUNTRIES_CSV=DE \
  FOCUS_COUNTRIES_CSV=DE \
  IPZIP_SAMPLE_PERCENT=10 \
  IPZIP_COUNTRY_MIN_CANDIDATES=5 \
  IPZIP_COUNTRY_MAX_CANDIDATES=12 \
  bash "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" >"$stdout_path" 2>"$stderr_path"

  local selected_count
  selected_count="$(wc -l < "$tmp_dir/work/selected-ip-443-focus-DE.txt" | tr -d ' ')"
  [[ "$selected_count" == "10" ]] || fail "expected DE focus sampling to keep 10 of 100 candidates, got $selected_count"
}

test_linux_runner_applies_country_sample_multipliers() {
  local tmp_dir zip_src zip_path stdout_path stderr_path
  tmp_dir="$(mktemp -d)"
  zip_src="$tmp_dir/zip-src"
  zip_path="$tmp_dir/ip.zip"
  stdout_path="$tmp_dir/script.stdout"
  stderr_path="$tmp_dir/script.stderr"

  mkdir -p "$zip_src/443"
  for i in $(seq 1 100); do
    printf '198.18.10.%s\n' "$i"
  done > "$zip_src/443/KR.txt"
  for i in $(seq 1 100); do
    printf '198.18.20.%s\n' "$i"
  done > "$zip_src/443/US.txt"
  (cd "$zip_src" && zip -qr "$zip_path" .)

  FORCE=1 \
  DRY_RUN=1 \
  ENABLE_CFBESTIP=0 \
  DOWNLOAD_URL="file://$zip_path" \
  WORK_DIR="$tmp_dir/work" \
  CFST_PATH="$tmp_dir/missing-cfst-ok-for-dry-run" \
  PORTS=443 \
  COUNTRIES_CSV=KR,US \
  FOCUS_COUNTRIES_CSV=KR,US \
  IPZIP_SAMPLE_PERCENT=20 \
  IPZIP_COUNTRY_MIN_CANDIDATES=0 \
  IPZIP_COUNTRY_MAX_CANDIDATES=100 \
  IPZIP_COUNTRY_SAMPLE_MULTIPLIERS="KR=2,US=0.5" \
  bash "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" >"$stdout_path" 2>"$stderr_path"

  local kr_count us_count
  kr_count="$(wc -l < "$tmp_dir/work/selected-ip-443-focus-KR.txt" | tr -d ' ')"
  us_count="$(wc -l < "$tmp_dir/work/selected-ip-443-focus-US.txt" | tr -d ' ')"
  [[ "$kr_count" == "40" ]] || fail "expected KR multiplier to keep 40 candidates, got $kr_count"
  [[ "$us_count" == "10" ]] || fail "expected US multiplier to keep 10 candidates, got $us_count"
}

test_linux_runner_excludes_focus_countries_from_all_scope() {
  local tmp_dir zip_src zip_path stdout_path stderr_path
  tmp_dir="$(mktemp -d)"
  zip_src="$tmp_dir/zip-src"
  zip_path="$tmp_dir/ip.zip"
  stdout_path="$tmp_dir/script.stdout"
  stderr_path="$tmp_dir/script.stderr"

  mkdir -p "$zip_src/443"
  printf '198.18.1.1\n' > "$zip_src/443/HK.txt"
  printf '198.18.2.1\n' > "$zip_src/443/DE.txt"
  (cd "$zip_src" && zip -qr "$zip_path" .)

  FORCE=1 \
  DRY_RUN=1 \
  ENABLE_CFBESTIP=0 \
  DOWNLOAD_URL="file://$zip_path" \
  WORK_DIR="$tmp_dir/work" \
  CFST_PATH="$tmp_dir/missing-cfst-ok-for-dry-run" \
  PORTS=443 \
  COUNTRIES_CSV=HK,DE \
  FOCUS_COUNTRIES_CSV=DE \
  bash "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" >"$stdout_path" 2>"$stderr_path"

  grep -q '^198\.18\.1\.1$' "$tmp_dir/work/selected-ip-443-all.txt" || fail "all scope should keep non-focus HK"
  if grep -q '^198\.18\.2\.1$' "$tmp_dir/work/selected-ip-443-all.txt"; then
    fail "all scope should exclude focus country DE"
  fi
}

test_linux_runner_waits_multiple_fast_cfst_jobs() {
  local tmp_dir zip_src zip_path stub_cfst stdout_path stderr_path
  tmp_dir="$(mktemp -d)"
  zip_src="$tmp_dir/zip-src"
  zip_path="$tmp_dir/ip.zip"
  stub_cfst="$tmp_dir/cfst"
  stdout_path="$tmp_dir/script.stdout"
  stderr_path="$tmp_dir/script.stderr"

  mkdir -p "$zip_src/443"
  printf '198.18.1.1\n' > "$zip_src/443/HK.txt"
  printf '198.18.2.1\n' > "$zip_src/443/DE.txt"
  printf '198.18.3.1\n' > "$zip_src/443/GB.txt"
  (cd "$zip_src" && zip -qr "$zip_path" .)

  cat > "$stub_cfst" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
input=""
out=""
while (($#)); do
  case "$1" in
    -f)
      input="$2"
      shift 2
      ;;
    -o)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
ip="$(head -n 1 "$input")"
{
  printf 'IP 地址,已发送,已接收,丢包率,平均延迟,下载速度(MB/s),地区码\n'
  printf '%s,1,1,0.00,100.00,1.00,HKG\n' "$ip"
} > "$out"
SH
  chmod +x "$stub_cfst"

  FORCE=1 \
  SKIP_UPLOAD=1 \
  ENABLE_CFBESTIP=0 \
  DOWNLOAD_URL="file://$zip_path" \
  WORK_DIR="$tmp_dir/work" \
  CFST_PATH="$stub_cfst" \
  PORTS=443 \
  COUNTRIES_CSV=HK,DE,GB \
  FOCUS_COUNTRIES_CSV=DE,GB \
  MAX_PARALLEL_CFST=1 \
  CFST_THREADS=1 \
  CFST_LATENCY_TEST_COUNT=1 \
  CFST_DOWNLOAD_TEST_COUNT=1 \
  CFST_DOWNLOAD_TEST_TIME=1 \
  FOCUS_CFST_DOWNLOAD_TEST_COUNT=1 \
  FOCUS_CFST_DOWNLOAD_TEST_TIME=1 \
  MIN_SPEED_MBPS=0 \
  bash "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" >"$stdout_path" 2>"$stderr_path"

  if grep -q 'pid .* is not a child of this shell' "$stderr_path" "$tmp_dir/work/auto-push.log"; then
    fail "runner should not wait for already-reaped cfst pids"
  fi
  grep -q 'SkipUpload enabled. CSV generated but GitHub upload and success-state update were skipped.' "$tmp_dir/work/auto-push.log" \
    || fail "runner should complete after multiple fast cfst jobs"
}

test_runner_defaults_include_europe_focus_countries() {
  grep -q 'COUNTRIES_CSV="${COUNTRIES_CSV:-HK,JP,KR,SG,PH,VN,MY,KZ,MN,IE,US,DE,GB,NL,IT}"' "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" \
    || fail "Linux runner default Countries should include DE/GB/NL/IT"
  grep -q 'FOCUS_COUNTRIES_CSV="${FOCUS_COUNTRIES_CSV:-SG,HK,JP,KR,DE,GB}"' "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" \
    || fail "Linux runner default FocusCountries should include SG/HK/JP/KR/DE/GB"
  grep -q '\[string\[\]\]\$Countries = @("HK", "JP", "KR", "SG", "PH", "VN", "MY", "KZ", "MN", "IE", "US", "DE", "GB", "NL", "IT")' "$ROOT_DIR/scripts/windows/Invoke-CFOptAutoPush.ps1" \
    || fail "Windows runner default Countries should include DE/GB/NL/IT"
  grep -q '\[string\]\$FocusCountries = "SG,HK,JP,KR,DE,GB"' "$ROOT_DIR/scripts/windows/Invoke-CFOptAutoPush.ps1" \
    || fail "Windows runner default FocusCountries should include SG/HK/JP/KR/DE/GB"
  grep -q 'IPZIP_COUNTRY_SAMPLE_MULTIPLIERS="${IPZIP_COUNTRY_SAMPLE_MULTIPLIERS:-KR=2,US=0.5}"' "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" \
    || fail "Linux runner should default to KR and US country sampling multipliers"
  grep -q '\[string\]\$IpZipCountrySampleMultipliers = "KR=2,US=0.5"' "$ROOT_DIR/scripts/windows/Invoke-CFOptAutoPush.ps1" \
    || fail "Windows runner should default to KR and US country sampling multipliers"
}

test_runners_default_to_four_hour_interval() {
  grep -q 'INTERVAL_HOURS="${INTERVAL_HOURS:-4}"' "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" \
    || fail "Linux runner should default to a 4-hour interval"
  grep -q 'INTERVAL_HOURS=4' "$ROOT_DIR/scripts/linux/install-and-run-cfopt-linux.sh" \
    || fail "Linux installer autorun should pass INTERVAL_HOURS=4"
  grep -q '\[int\]\$IntervalHours = 4' "$ROOT_DIR/scripts/windows/Invoke-CFOptAutoPush.ps1" \
    || fail "Windows runner should default to a 4-hour interval"
  grep -q -- '-IntervalHours 4' "$ROOT_DIR/scripts/windows/Install-CFOptAutoPushTask.ps1" \
    || fail "Windows scheduled task should pass -IntervalHours 4"
}

test_focus_scopes_use_quick_download_screening() {
  grep -q 'FOCUS_CFST_DOWNLOAD_TEST_COUNT="${FOCUS_CFST_DOWNLOAD_TEST_COUNT:-12}"' "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" \
    || fail "Linux focus scopes should default to a smaller download-test count"
  grep -q 'FOCUS_CFST_DOWNLOAD_TEST_TIME="${FOCUS_CFST_DOWNLOAD_TEST_TIME:-8}"' "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" \
    || fail "Linux focus scopes should default to a shorter download-test time"
  grep -q '\[int\]\$FocusCfstDownloadTestCount = 12' "$ROOT_DIR/scripts/windows/Invoke-CFOptAutoPush.ps1" \
    || fail "Windows focus scopes should default to a smaller download-test count"
  grep -q '\[int\]\$FocusCfstDownloadTestTime = 8' "$ROOT_DIR/scripts/windows/Invoke-CFOptAutoPush.ps1" \
    || fail "Windows focus scopes should default to a shorter download-test time"
}

test_proxyip_best_generator_ranks_candidates_by_tcp_latency() {
  local tmp_dir source_txt output_txt ready_file
  tmp_dir="$(mktemp -d)"
  source_txt="$tmp_dir/all.txt"
  output_txt="$tmp_dir/proxyip-best.txt"
  ready_file="$tmp_dir/ready"

  python3 - "$ready_file" <<'PY' &
import socket
import re
import sys
import threading
import time

ready = sys.argv[1]

def server(port, delay):
    sock = socket.socket()
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", port))
    sock.listen()
    while True:
        conn, _ = sock.accept()
        time.sleep(delay)
        conn.close()

threading.Thread(target=server, args=(19081, 0.001), daemon=True).start()
threading.Thread(target=server, args=(19082, 0.05), daemon=True).start()
open(ready, "w").close()
while True:
    time.sleep(1)
PY
  local server_pid=$!
  for _ in $(seq 1 50); do
    [[ -f "$ready_file" ]] && break
    sleep 0.1
  done

  cat > "$source_txt" <<'TXT'
127.0.0.1:19082#SG
127.0.0.1:19081#SG
TXT

  python3 "$ROOT_DIR/scripts/generate_proxyip_best.py" \
    --source "file://$source_txt" \
    --output "$output_txt" \
    --countries SG \
    --limit 1 \
    --timeout 0.5 \
    --workers 2
  kill "$server_pid" 2>/dev/null || true

  grep -q '^127\.0\.0\.1:19081#SG$' "$output_txt" || fail "proxyip best generator should keep the fastest SG proxyip"
  if grep -q '^127\.0\.0\.1:19082#SG$' "$output_txt"; then
    fail "proxyip best generator kept the slower SG proxyip"
  fi
}

test_subconverter_group_order_and_pool_names() {
  local config
  for config in "$ROOT_DIR/CFOpt_Subconverter.ini" "$ROOT_DIR/CFOpt_Subconverter_lite.ini" "$ROOT_DIR/CFOpt_Subconverter_lite_cmliussss.ini"; do
    python3 - "$config" <<'PY'
import re
import sys

path = sys.argv[1]
groups = []
with open(path, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if line.startswith("custom_proxy_group="):
            name = line[len("custom_proxy_group="):].split("`", 1)[0]
            groups.append(name)

expected = [
    "Proxy",
    "CodeAgent",
    "Polymarket",
    "OKX",
]

if path.endswith("_lite.ini") or path.endswith("_lite_cmliussss.ini"):
    expected.extend([
        "CodeAgent JP Pool",
        "CodeAgent KR Pool",
        "CodeAgent SG Pool",
        "CodeAgent HK Pool",
        "Polymarket DE + IE Pool",
        "Polymarket DE + AT Pool",
        "Polymarket KR Pool",
        "Polymarket GB + IE Pool",
        "OKX HK Pool",
        "OKX KR Pool",
        "OKX SG Pool",
        "DE + IE Pool",
        "DE + AT Pool",
        "GB + IE Pool",
        "HK Pool",
        "JP Pool",
        "KR Pool",
        "SG Pool",
        "US Pool",
        "DE Pool",
        "GB Pool",
        "Auto",
        "Fallback",
        "Direct",
        "Final",
    ])
else:
    expected.extend([
    "CodeAgent 🇯🇵 Japan Pool",
    "CodeAgent 🇰🇷 Korea Pool",
    "CodeAgent 🇸🇬 Singapore Pool",
    "CodeAgent 🇭🇰 Hong Kong Pool",
    "Polymarket 🇩🇪 Germany Entry + 🇮🇪 IE Proxy",
    "Polymarket 🇩🇪 Germany Entry + 🇦🇹 AT Proxy",
    "Polymarket 🇰🇷 Korea Pool",
    "Polymarket 🇬🇧 United Kingdom Entry + 🇮🇪 IE Proxy",
    "OKX 🇭🇰 Hong Kong Pool",
    "OKX 🇰🇷 Korea Pool",
    "OKX 🇸🇬 Singapore Pool",
    "Asia Pool",
    "🇩🇪 Germany Entry + 🇮🇪 IE Proxy",
    "🇩🇪 Germany Entry + 🇦🇹 AT Proxy",
    "🇬🇧 United Kingdom Entry + 🇮🇪 IE Proxy",
    "🇭🇰 Hong Kong Pool",
    "🇯🇵 Japan Pool",
    "🇰🇷 Korea Pool",
    "🇸🇬 Singapore Pool",
    "🇬🇧 United Kingdom Pool",
    "CT Pool",
    "Domain Pool",
    ])

position = -1
for name in expected:
    try:
        position = groups.index(name, position + 1)
    except ValueError:
        raise SystemExit(f"{path}: missing or misordered group {name!r}")

for legacy in [
    "HKPool",
    "JPPool",
    "KRPool",
    "SGPool",
    "DEPool",
    "GBPool",
    "NLPool",
    "ITPool",
    "AsiaPool",
    "CFCTPool",
    "DomainPreferredPool",
]:
    if legacy in groups:
        raise SystemExit(f"{path}: legacy group name still present: {legacy}")

with open(path, encoding="utf-8") as fh:
    text = fh.read()

if "github.com/GuardSkill/CFOpt/raw/refs/heads/main" in text:
    raise SystemExit(f"{path}: use raw.githubusercontent.com URLs for cmliussss compatibility")

if "rules/Bilibili.list" in text and "ruleset=Direct,https://raw.githubusercontent.com/GuardSkill/CFOpt/main/rules/Bilibili.list" not in text:
    raise SystemExit(f"{path}: Bilibili rules must route to Direct")

if path.endswith("_lite.ini") or path.endswith("_lite_cmliussss.ini"):
    required_lines = [
        "custom_proxy_group=Proxy`select`[]CodeAgent`[]Polymarket`[]OKX`[]Twitter`[]DE + IE Pool`[]DE + AT Pool`[]GB + IE Pool`[]HK Pool`[]JP Pool`[]KR Pool`[]SG Pool`[]DE Pool`[]GB Pool`[]US Pool`[]Auto`[]Fallback`[]DIRECT`.*",
        "custom_proxy_group=CodeAgent`select`[]CodeAgent JP Pool`[]CodeAgent KR Pool`[]CodeAgent SG Pool`[]CodeAgent HK Pool`[]Auto`[]DIRECT",
        "custom_proxy_group=Polymarket`select`[]Polymarket DE + IE Pool`[]Polymarket DE + AT Pool`[]Polymarket KR Pool`[]Polymarket GB + IE Pool`[]Auto`[]DIRECT",
        "custom_proxy_group=OKX`select`[]OKX HK Pool`[]OKX KR Pool`[]OKX SG Pool`[]Auto`[]DIRECT",
        "custom_proxy_group=Twitter`select`[]JP Pool`[]KR Pool`[]SG Pool`[]HK Pool`[]Auto`[]DIRECT",
        "custom_proxy_group=CodeAgent JP Pool`url-test`(^| )JP ↪ \\[`https://api.anthropic.com/`3600,,50",
        "custom_proxy_group=Polymarket KR Pool`url-test`(^| )KR ↪ \\[`https://gamma-api.polymarket.com/markets?active=true&closed=false&limit=1`3600,,50",
        "custom_proxy_group=OKX HK Pool`url-test`(^| )HK ↪ \\[`https://www.okx.com/api/v5/market/ticker?instId=BTC-USDT`3600,,50",
        "custom_proxy_group=DE + IE Pool`url-test`DE .*IE \\[",
        "custom_proxy_group=DE + AT Pool`url-test`DE .*AT \\[",
        "custom_proxy_group=GB + IE Pool`url-test`GB .*IE \\[",
        "custom_proxy_group=HK Pool`url-test`(^| )(🇭🇰 )?HK( ↪)? \\[",
        "custom_proxy_group=JP Pool`url-test`(^| )(🇯🇵 )?JP( ↪)? \\[",
        "custom_proxy_group=KR Pool`url-test`(^| )(🇰🇷 )?KR( ↪)? \\[",
        "custom_proxy_group=SG Pool`url-test`(^| )(🇸🇬 )?SG( ↪)? \\[",
        "custom_proxy_group=US Pool`url-test`(^| )(US) \\[",
        "custom_proxy_group=DE Pool`url-test`(^| )(DE) \\[",
        "custom_proxy_group=GB Pool`url-test`(^| )(GB) \\[",
        "custom_proxy_group=Auto`url-test`.*`",
        "custom_proxy_group=Fallback`fallback`.*`",
        "custom_proxy_group=Final`select`[]Proxy`[]CodeAgent`[]Auto`[]Polymarket`[]OKX`[]Twitter`[]Fallback`[]DIRECT`.*",
    ]
else:
    required_lines = [
        "custom_proxy_group=Proxy`select`[]CodeAgent`[]Polymarket`[]OKX`[]Twitter`[]Auto`[]LB-20min`[]Fallback`[]DIRECT`.*",
        "custom_proxy_group=CodeAgent`select`[]CodeAgent 🇯🇵 Japan Pool`[]CodeAgent 🇰🇷 Korea Pool`[]CodeAgent 🇸🇬 Singapore Pool`[]CodeAgent 🇭🇰 Hong Kong Pool",
        "custom_proxy_group=Polymarket`select`[]Polymarket 🇩🇪 Germany Entry + 🇮🇪 IE Proxy`[]Polymarket 🇩🇪 Germany Entry + 🇦🇹 AT Proxy`[]Polymarket 🇰🇷 Korea Pool`[]Polymarket 🇬🇧 United Kingdom Entry + 🇮🇪 IE Proxy",
        "custom_proxy_group=OKX`select`[]OKX 🇭🇰 Hong Kong Pool`[]OKX 🇰🇷 Korea Pool`[]OKX 🇸🇬 Singapore Pool",
        "custom_proxy_group=Twitter`select`[]🇯🇵 Japan Pool`[]🇰🇷 Korea Pool`[]🇸🇬 Singapore Pool`[]🇭🇰 Hong Kong Pool`[]Auto`[]DIRECT",
        "custom_proxy_group=CodeAgent 🇯🇵 Japan Pool`url-test`^.*JP ↪ \\[`https://api.anthropic.com/`3600,,50",
        "custom_proxy_group=Polymarket 🇰🇷 Korea Pool`url-test`^.*KR ↪ \\[`https://gamma-api.polymarket.com/markets?active=true&closed=false&limit=1`3600,,50",
        "custom_proxy_group=OKX 🇭🇰 Hong Kong Pool`url-test`^.*HK ↪ \\[`https://www.okx.com/api/v5/market/ticker?instId=BTC-USDT`3600,,50",
        "custom_proxy_group=Auto`url-test`\\[(BJ|CD)#0[1-5]\\s|测速#?0[1-5]\\s|电信`",
        "custom_proxy_group=LB-20min`load-balance`\\[(BJ|CD)#0[1-5]\\s|测速#?0[1-5]\\s|电信`",
        "custom_proxy_group=Fallback`fallback`\\[(BJ|CD)#0[1-5]\\s|测速#?0[1-5]\\s|电信`",
    ]

for required in required_lines:
    if required not in text:
        raise SystemExit(f"{path}: missing simplified routing group: {required}")

url_test_regexes = {}
for raw_line in text.splitlines():
    if not raw_line.startswith("custom_proxy_group="):
        continue
    parts = raw_line[len("custom_proxy_group="):].split("`")
    if len(parts) >= 4 and parts[1] == "url-test":
        url_test_regexes[parts[0]] = parts[2]

def python_regex_from_pcre(pattern):
    return re.sub(r"\\x\{([0-9A-Fa-f]+)\}", lambda m: chr(int(m.group(1), 16)), pattern)

if path.endswith("_lite.ini") or path.endswith("_lite_cmliussss.ini"):
    regex_samples = {
        "OKX HK Pool": ["🇭🇰 HK ↪ [BJ#01 ip.zip]"],
        "OKX KR Pool": ["🇰🇷 KR ↪ [BJ#01 ip.zip]"],
        "OKX SG Pool": ["🇸🇬 SG ↪ [BJ#01 ip.zip]"],
        "CodeAgent JP Pool": ["🇯🇵 JP ↪ [BJ#01 ip.zip]"],
        "CodeAgent KR Pool": ["🇰🇷 KR ↪ [BJ#01 ip.zip]"],
        "CodeAgent SG Pool": ["🇸🇬 SG ↪ [BJ#01 ip.zip]"],
        "CodeAgent HK Pool": ["🇭🇰 HK ↪ [BJ#01 ip.zip]"],
        "Polymarket DE + IE Pool": ["🇩🇪 DE → 🇮🇪 IE [BJ#01 ip.zip]"],
        "Polymarket DE + AT Pool": ["🇩🇪 DE → 🇦🇹 AT [BJ#01 ip.zip]"],
        "Polymarket KR Pool": ["🇰🇷 KR ↪ [BJ#01 ip.zip]"],
        "Polymarket GB + IE Pool": ["🇬🇧 GB → 🇮🇪 IE [BJ#01 ip.zip]"],
        "HK Pool": ["🇭🇰 HK ↪ [BJ#01 ip.zip]", "HK [BJ#01 ip.zip]"],
        "JP Pool": ["🇯🇵 JP ↪ [BJ#01 ip.zip]", "JP [BJ#01 ip.zip]"],
        "KR Pool": ["🇰🇷 KR ↪ [BJ#01 ip.zip]", "KR [BJ#01 ip.zip]"],
        "SG Pool": ["🇸🇬 SG ↪ [BJ#01 ip.zip]", "SG [BJ#01 ip.zip]"],
    }
else:
    regex_samples = {
        "OKX 🇭🇰 Hong Kong Pool": ["🇭🇰 HK ↪ [BJ#01 ip.zip]"],
        "OKX 🇰🇷 Korea Pool": ["🇰🇷 KR ↪ [BJ#01 ip.zip]"],
        "OKX 🇸🇬 Singapore Pool": ["🇸🇬 SG ↪ [BJ#01 ip.zip]"],
        "CodeAgent 🇯🇵 Japan Pool": ["🇯🇵 JP ↪ [BJ#01 ip.zip]"],
        "CodeAgent 🇰🇷 Korea Pool": ["🇰🇷 KR ↪ [BJ#01 ip.zip]"],
        "CodeAgent 🇸🇬 Singapore Pool": ["🇸🇬 SG ↪ [BJ#01 ip.zip]"],
        "CodeAgent 🇭🇰 Hong Kong Pool": ["🇭🇰 HK ↪ [BJ#01 ip.zip]"],
        "Polymarket 🇩🇪 Germany Entry + 🇮🇪 IE Proxy": ["🇩🇪 DE → 🇮🇪 IE [BJ#01 ip.zip]"],
        "Polymarket 🇩🇪 Germany Entry + 🇦🇹 AT Proxy": ["🇩🇪 DE → 🇦🇹 AT [BJ#01 ip.zip]"],
        "Polymarket 🇰🇷 Korea Pool": ["🇰🇷 KR ↪ [BJ#01 ip.zip]"],
        "Polymarket 🇬🇧 United Kingdom Entry + 🇮🇪 IE Proxy": ["🇬🇧 GB → 🇮🇪 IE [BJ#01 ip.zip]"],
        "🇭🇰 Hong Kong Pool": ["🇭🇰 HK ↪ [BJ#01 ip.zip]", "HK [BJ#01 ip.zip]"],
        "🇯🇵 Japan Pool": ["🇯🇵 JP ↪ [BJ#01 ip.zip]", "JP [BJ#01 ip.zip]"],
        "🇰🇷 Korea Pool": ["🇰🇷 KR ↪ [BJ#01 ip.zip]", "KR [BJ#01 ip.zip]"],
        "🇸🇬 Singapore Pool": ["🇸🇬 SG ↪ [BJ#01 ip.zip]", "SG [BJ#01 ip.zip]"],
    }

for group, samples in regex_samples.items():
    pattern = url_test_regexes.get(group)
    if not pattern:
        raise SystemExit(f"{path}: missing url-test regex for group {group!r}")
    pattern = python_regex_from_pcre(pattern)
    for sample in samples:
        if not re.search(pattern, sample):
            raise SystemExit(f"{path}: group {group!r} regex {pattern!r} does not match sample node {sample!r}")

if path.endswith("_lite.ini") or path.endswith("_lite_cmliussss.ini"):
    business_reject_samples = {
        "OKX HK Pool": ["🇭🇰 HK [BJ#01 ip.zip]", "HK [BJ#01 ip.zip]"],
        "OKX KR Pool": ["🇰🇷 KR [BJ#01 ip.zip]", "KR [BJ#01 ip.zip]"],
        "OKX SG Pool": ["🇸🇬 SG [BJ#01 ip.zip]", "SG [BJ#01 ip.zip]"],
        "CodeAgent JP Pool": ["🇯🇵 JP [BJ#01 ip.zip]", "JP [BJ#01 ip.zip]"],
        "CodeAgent KR Pool": ["🇰🇷 KR [BJ#01 ip.zip]", "KR [BJ#01 ip.zip]"],
        "CodeAgent SG Pool": ["🇸🇬 SG [BJ#01 ip.zip]", "SG [BJ#01 ip.zip]"],
        "CodeAgent HK Pool": ["🇭🇰 HK [BJ#01 ip.zip]", "HK [BJ#01 ip.zip]"],
        "Polymarket KR Pool": ["🇰🇷 KR [BJ#01 ip.zip]", "KR [BJ#01 ip.zip]"],
    }
else:
    business_reject_samples = {
        "OKX 🇭🇰 Hong Kong Pool": ["🇭🇰 HK [BJ#01 ip.zip]"],
        "OKX 🇰🇷 Korea Pool": ["🇰🇷 KR [BJ#01 ip.zip]"],
        "OKX 🇸🇬 Singapore Pool": ["🇸🇬 SG [BJ#01 ip.zip]"],
        "CodeAgent 🇯🇵 Japan Pool": ["🇯🇵 JP [BJ#01 ip.zip]"],
        "CodeAgent 🇰🇷 Korea Pool": ["🇰🇷 KR [BJ#01 ip.zip]"],
        "CodeAgent 🇸🇬 Singapore Pool": ["🇸🇬 SG [BJ#01 ip.zip]"],
        "CodeAgent 🇭🇰 Hong Kong Pool": ["🇭🇰 HK [BJ#01 ip.zip]"],
        "Polymarket 🇰🇷 Korea Pool": ["🇰🇷 KR [BJ#01 ip.zip]"],
    }

for group, samples in business_reject_samples.items():
    pattern = url_test_regexes.get(group)
    if not pattern:
        raise SystemExit(f"{path}: missing url-test regex for business group {group!r}")
    for sample in samples:
        if re.search(pattern, sample):
            raise SystemExit(f"{path}: business group {group!r} regex {pattern!r} should only match proxyip chain nodes, but matched {sample!r}")

if not (path.endswith("_lite.ini") or path.endswith("_lite_cmliussss.ini")):
    for required in [
        "custom_proxy_group=🇩🇪 Germany Entry + 🇮🇪 IE Proxy`url-test`^(🇩🇪|🇮🇪) DE → 🇮🇪 IE \\[",
        "custom_proxy_group=🇩🇪 Germany Entry + 🇦🇹 AT Proxy`url-test`^(🇩🇪|🇦🇹) DE → 🇦🇹 AT \\[",
        "custom_proxy_group=🇬🇧 United Kingdom Entry + 🇮🇪 IE Proxy`url-test`^🇬🇧 GB → 🇮🇪 IE \\[",
        "custom_proxy_group=🇭🇰 Hong Kong Pool`url-test`^(🇭🇰 )?HK( ↪)? \\[",
        "custom_proxy_group=🇯🇵 Japan Pool`url-test`^(🇯🇵 )?JP( ↪)? \\[",
        "custom_proxy_group=🇰🇷 Korea Pool`url-test`^(🇰🇷 )?KR( ↪)? \\[",
        "custom_proxy_group=🇸🇬 Singapore Pool`url-test`^(🇸🇬 )?SG( ↪)? \\[",
        "custom_proxy_group=🇬🇧 United Kingdom Pool`url-test`^(🇬🇧 GB → 🇮🇪 IE|GB) \\[",
    ]:
        if required not in text:
            raise SystemExit(f"{path}: missing proxyip-only pool matcher: {required}")

for forbidden in [
    "馃",
    "北京测速",
    "成都测速",
    "custom_proxy_group=🇭🇰 Hong Kong Pool`url-test`^🇭🇰",
    "custom_proxy_group=🇯🇵 Japan Pool`url-test`^🇯🇵",
    "custom_proxy_group=🇰🇷 Korea Pool`url-test`^🇰🇷",
    "custom_proxy_group=🇸🇬 Singapore Pool`url-test`^🇸🇬",
    "custom_proxy_group=Asia Pool`url-test`[]🇭🇰 Hong Kong Pool`[]🇯🇵 Japan Pool`[]🇰🇷 Korea Pool`[]🇸🇬 Singapore Pool`^(PH|VN|MY|KZ|MN)",
    "custom_proxy_group=Region",
]:
    if forbidden in text:
        raise SystemExit(f"{path}: ordinary nodes still match a proxyip pool: {forbidden}")

if (path.endswith("_lite.ini") or path.endswith("_lite_cmliussss.ini")) and "custom_proxy_group=LB-20min" in text:
    raise SystemExit(f"{path}: lite config should not include LB-20min")
PY
  done
}

test_tracked_csv_node_labels_are_ascii_safe() {
  for csv in "$ROOT_DIR/CloudflareSpeedTest_BJ.csv" "$ROOT_DIR/CloudflareSpeedTest_CD.csv"; do
    if grep -Eq '馃|北京测速|成都测速' "$csv"; then
      fail "tracked CSV contains mojibake or old location labels: $csv"
    fi
  done
}

test_polymarket_rules_cover_core_api_domains() {
  local rules_file="$ROOT_DIR/rules/Polymarket.list"
  local required_rules=(
    "DOMAIN-SUFFIX,gamma-api.polymarket.com"
    "DOMAIN-SUFFIX,data-api.polymarket.com"
    "DOMAIN-SUFFIX,clob.polymarket.com"
    "DOMAIN-SUFFIX,ws-subscriptions-clob.polymarket.com"
    "DOMAIN-SUFFIX,ws-subscriptions-user.polymarket.com"
    "DOMAIN-SUFFIX,bridge.polymarket.com"
    "DOMAIN-SUFFIX,polymarket.com"
    "DOMAIN-SUFFIX,polymarketcdn.com"
    "DOMAIN-KEYWORD,polymarket"
    "DOMAIN-KEYWORD,thegraph"
  )

  for rule in "${required_rules[@]}"; do
    grep -qxF "$rule" "$rules_file" || fail "Polymarket rules missing: $rule"
  done
}

test_polymarket_rules_are_inlined_in_subconverter_configs() {
  local config
  local required_rules=(
    "ruleset=Polymarket,[]DOMAIN-SUFFIX,gamma-api.polymarket.com"
    "ruleset=Polymarket,[]DOMAIN-SUFFIX,data-api.polymarket.com"
    "ruleset=Polymarket,[]DOMAIN-SUFFIX,clob.polymarket.com"
    "ruleset=Polymarket,[]DOMAIN-SUFFIX,ws-subscriptions-clob.polymarket.com"
    "ruleset=Polymarket,[]DOMAIN-SUFFIX,ws-subscriptions-user.polymarket.com"
    "ruleset=Polymarket,[]DOMAIN-SUFFIX,bridge.polymarket.com"
    "ruleset=Polymarket,[]DOMAIN-SUFFIX,polymarket.com"
    "ruleset=Polymarket,[]DOMAIN-SUFFIX,polymarketcdn.com"
    "ruleset=Polymarket,[]DOMAIN-KEYWORD,polymarket"
    "ruleset=Polymarket,[]DOMAIN-KEYWORD,thegraph"
  )

  for config in "$ROOT_DIR/CFOpt_Subconverter.ini" "$ROOT_DIR/CFOpt_Subconverter_lite.ini" "$ROOT_DIR/CFOpt_Subconverter_lite_cmliussss.ini"; do
    for rule in "${required_rules[@]}"; do
      grep -qxF "$rule" "$config" || fail "$config missing inline Polymarket rule: $rule"
    done

    if grep -q '^ruleset=Polymarket,https://' "$config"; then
      fail "$config should inline Polymarket rules instead of depending on remote rule fetch"
    fi
  done
}

test_twitter_rules_cover_core_domains() {
  local rules_file="$ROOT_DIR/rules/Twitter.list"
  local required_rules=(
    "DOMAIN-SUFFIX,x.com"
    "DOMAIN-SUFFIX,twitter.com"
    "DOMAIN-SUFFIX,t.co"
    "DOMAIN-SUFFIX,twimg.com"
    "DOMAIN-SUFFIX,tweetdeck.com"
  )

  for rule in "${required_rules[@]}"; do
    grep -qxF "$rule" "$rules_file" || fail "Twitter rules missing: $rule"
  done
}

test_twitter_rules_are_referenced_in_subconverter_configs() {
  local config
  local rule="ruleset=Twitter,https://raw.githubusercontent.com/GuardSkill/CFOpt/main/rules/Twitter.list"

  for config in "$ROOT_DIR/CFOpt_Subconverter.ini" "$ROOT_DIR/CFOpt_Subconverter_lite.ini" "$ROOT_DIR/CFOpt_Subconverter_lite_cmliussss.ini"; do
    grep -qxF "$rule" "$config" || fail "$config missing Twitter ruleset: $rule"
  done
}

test_cfst_log_prefix_handles_scopes
test_linux_defaults_are_not_overly_strict_for_local_runs
test_linux_runner_samples_large_country_files
test_linux_runner_applies_country_sample_multipliers
test_linux_runner_excludes_focus_countries_from_all_scope
test_linux_runner_waits_multiple_fast_cfst_jobs
test_runner_defaults_include_europe_focus_countries
test_runners_default_to_four_hour_interval
test_focus_scopes_use_quick_download_screening
test_proxyip_best_generator_ranks_candidates_by_tcp_latency
test_subconverter_group_order_and_pool_names
test_tracked_csv_node_labels_are_ascii_safe
test_polymarket_rules_cover_core_api_domains
test_polymarket_rules_are_inlined_in_subconverter_configs
test_twitter_rules_cover_core_domains
test_twitter_rules_are_referenced_in_subconverter_configs

printf 'Linux script tests passed.\n'
