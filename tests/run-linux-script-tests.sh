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

test_proxyip_best_generator_allows_country_specific_limits() {
  local tmp_dir source_txt output_txt
  tmp_dir="$(mktemp -d)"
  source_txt="$tmp_dir/all.txt"
  output_txt="$tmp_dir/proxyip-best.txt"

  {
    for i in $(seq 1 12); do
      printf '127.0.1.%s:443#HK\n' "$i"
    done
    for i in $(seq 1 12); do
      printf '127.0.2.%s:443#SG\n' "$i"
    done
  } > "$source_txt"

  python3 "$ROOT_DIR/scripts/generate_proxyip_best.py" \
    --source "file://$source_txt" \
    --output "$output_txt" \
    --countries HK,SG \
    --limit 2 \
    --country-limits HK=5 \
    --timeout 0.01 \
    --workers 4

  local hk_count sg_count
  hk_count="$(grep -c '#HK$' "$output_txt" || true)"
  sg_count="$(grep -c '#SG$' "$output_txt" || true)"
  [[ "$hk_count" == "5" ]] || fail "expected HK country-specific proxyip limit to keep 5 candidates, got $hk_count"
  [[ "$sg_count" == "2" ]] || fail "expected default proxyip limit to keep 2 SG candidates, got $sg_count"
}

test_subconverter_group_order_and_pool_names() {
  python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
full = root / "CFOpt_Subconverter.ini"
lite = root / "CFOpt_Subconverter_lite.ini"
cmliussss = root / "CFOpt_Subconverter_lite_cmliussss.ini"
deleted = root / "CFOpt_Subconverter_lite_twitter_plain.ini"

if deleted.exists():
    raise SystemExit(f"{deleted}: obsolete experimental config should be deleted")

def lines(path, prefix):
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip().startswith(prefix)]

def text(path):
    return path.read_text(encoding="utf-8")

lite_rules = lines(lite, "ruleset=")
cmliussss_rules = lines(cmliussss, "ruleset=")
lite_groups = lines(lite, "custom_proxy_group=")
cmliussss_groups = lines(cmliussss, "custom_proxy_group=")

if lite_rules != cmliussss_rules:
    raise SystemExit("CFOpt_Subconverter_lite.ini rulesets must match CFOpt_Subconverter_lite_cmliussss.ini")
if lite_groups != cmliussss_groups:
    raise SystemExit("CFOpt_Subconverter_lite.ini proxy groups must match CFOpt_Subconverter_lite_cmliussss.ini")

full_rules = set(lines(full, "ruleset="))
for rule in cmliussss_rules:
    if rule not in full_rules:
        raise SystemExit(f"{full}: missing lite baseline ruleset: {rule}")

required_business_groups = [
    "custom_proxy_group=CodeAgent`select`[]JP Proxy ↪`[]HK Proxy ↪`[]KR Proxy ↪`[]SG Proxy ↪`[]Auto`[]DIRECT",
    "custom_proxy_group=Polymarket`select`[]Polymarket DE + IE Pool`[]Polymarket DE + AT Pool`[]KR Proxy ↪`[]Polymarket GB + IE Pool`[]Auto`[]DIRECT",
    "custom_proxy_group=OKX`select`[]OKX HK Proxy ↪`[]KR Proxy ↪`[]SG Proxy ↪`[]Auto`[]DIRECT",
    "custom_proxy_group=Twitter`select`[]JP Pool`[]KR Pool`[]SG Pool`[]HK Pool`[]Auto`[]DIRECT",
    "custom_proxy_group=Steam`select`[]JP Pool`[]KR Pool`[]SG Pool`[]HK Pool`[]Auto`[]DIRECT",
]
full_text = text(full)
for group in required_business_groups:
    if group not in full_text:
        raise SystemExit(f"{full}: missing aligned business group: {group}")

for path in [full, lite, cmliussss]:
    content = text(path)
    if "github.com/GuardSkill/CFOpt/raw/refs/heads/main" in content:
        raise SystemExit(f"{path}: use raw.githubusercontent.com URLs for cmliussss compatibility")
    if "rules/Bilibili.list" in content and "ruleset=Direct,https://raw.githubusercontent.com/GuardSkill/CFOpt/main/rules/Bilibili.list" not in content:
        raise SystemExit(f"{path}: Bilibili rules must route to Direct")
    if "custom_proxy_group=CodeAgent`select`[]JP Proxy ↪`[]HK Proxy ↪`[]KR Proxy ↪`[]SG Proxy ↪`[]Auto`[]DIRECT" not in content:
        raise SystemExit(f"{path}: CodeAgent must default to JP Proxy first")
    if "ruleset=Steam,https://raw.githubusercontent.com/GuardSkill/CFOpt/main/rules/Steam.list" not in content:
        raise SystemExit(f"{path}: missing Steam ruleset")
    if "custom_proxy_group=Steam`select`[]JP Pool`[]KR Pool`[]SG Pool`[]HK Pool`[]Auto`[]DIRECT" not in content:
        raise SystemExit(f"{path}: Steam must use plain country pools like Twitter")
    steam_group = next((line for line in lines(path, "custom_proxy_group=Steam`select`")), "")
    if "Proxy ↪" in steam_group or "[]Proxy" in steam_group:
        raise SystemExit(f"{path}: Steam must not use Proxy or ProxyIP chain groups: {steam_group}")
    if "custom_proxy_group=OKX HK Proxy ↪`url-test`^.*HK ↪ \\[`https://www.okx.com/api/v5/market/ticker?instId=BTC-USDT`780,,50" not in content:
        raise SystemExit(f"{path}: OKX HK Proxy must retest every 13 minutes")
    if "custom_proxy_group=HK Proxy ↪`url-test`^.*HK ↪ \\[`https://www.okx.com/api/v5/market/ticker?instId=BTC-USDT`" in content:
        raise SystemExit(f"{path}: OKX must not reuse the shared HK Proxy group")
    polymarket_test_url = "https://clob.polymarket.com/markets?next_cursor="
    polymarket_url_test_groups = [
        line for line in lines(path, "custom_proxy_group=")
        if "`url-test`" in line and ("Polymarket" in line or "gamma-api.polymarket.com" in line or "clob.polymarket.com" in line)
    ]
    for group in polymarket_url_test_groups:
        if polymarket_test_url not in group:
            raise SystemExit(f"{path}: Polymarket url-test must use stable CLOB markets URL: {group}")
    if "book?token_id=" in content:
        raise SystemExit(f"{path}: Polymarket url-test must not use changing book token URLs")
    plain_pool_patterns = {
        "HK Pool": ["🇭🇰 HK [BJ#01 ip.zip]", "🇭🇰 HK ↪ [BJ#01 ip.zip]"],
        "JP Pool": ["🇯🇵 JP [BJ#01 ip.zip]", "🇯🇵 JP ↪ [BJ#01 ip.zip]"],
        "KR Pool": ["🇰🇷 KR [BJ#01 ip.zip]", "🇰🇷 KR ↪ [BJ#01 ip.zip]"],
        "SG Pool": ["🇸🇬 SG [BJ#01 ip.zip]", "🇸🇬 SG ↪ [BJ#01 ip.zip]"],
    }
    groups = {}
    for line in lines(path, "custom_proxy_group="):
        parts = line[len("custom_proxy_group="):].split("`")
        if len(parts) >= 3 and parts[1] == "url-test":
            groups[parts[0]] = parts[2]
    for group, samples in plain_pool_patterns.items():
        pattern = groups.get(group)
        if not pattern:
            raise SystemExit(f"{path}: missing plain country pool: {group}")
        if "↪" in pattern:
            raise SystemExit(f"{path}: {group} must only match plain nodes, got {pattern}")
        if not re.search(pattern, samples[0]):
            raise SystemExit(f"{path}: {group} does not match plain node {samples[0]!r}")
        if re.search(pattern, samples[1]):
            raise SystemExit(f"{path}: {group} must not match ProxyIP node {samples[1]!r}")
    for forbidden in ["馃", "北京测速", "成都测速", "custom_proxy_group=Region"]:
        if forbidden in content:
            raise SystemExit(f"{path}: forbidden stale content found: {forbidden}")
    if path.name.startswith("CFOpt_Subconverter_lite") and "custom_proxy_group=LB-20min" in content:
        raise SystemExit(f"{path}: lite config should not include LB-20min")
PY
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
    "DOMAIN-SUFFIX,periscope.tv"
    "DOMAIN-SUFFIX,pscp.tv"
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

test_steam_rules_cover_core_store_community_and_cdn_domains() {
  local rules_file="$ROOT_DIR/rules/Steam.list"
  local required_rules=(
    "DOMAIN-SUFFIX,steampowered.com"
    "DOMAIN-SUFFIX,steamcommunity.com"
    "DOMAIN-SUFFIX,steam-chat.com"
    "DOMAIN-SUFFIX,steamstatic.com"
    "DOMAIN-SUFFIX,steamcontent.com"
    "DOMAIN-SUFFIX,steamusercontent.com"
    "DOMAIN-SUFFIX,steamserver.net"
    "DOMAIN-SUFFIX,valvesoftware.com"
    "DOMAIN,steamcdn-a.akamaihd.net"
    "DOMAIN,steamcommunity-a.akamaihd.net"
    "DOMAIN,steamstore-a.akamaihd.net"
    "DOMAIN,steamusercontent-a.akamaihd.net"
  )

  for rule in "${required_rules[@]}"; do
    grep -qxF "$rule" "$rules_file" || fail "Steam rules missing: $rule"
  done
}

test_steam_rules_are_referenced_in_subconverter_configs() {
  local config
  local rule="ruleset=Steam,https://raw.githubusercontent.com/GuardSkill/CFOpt/main/rules/Steam.list"

  for config in "$ROOT_DIR/CFOpt_Subconverter.ini" "$ROOT_DIR/CFOpt_Subconverter_lite.ini" "$ROOT_DIR/CFOpt_Subconverter_lite_cmliussss.ini"; do
    grep -qxF "$rule" "$config" || fail "$config missing Steam ruleset: $rule"
  done
}

test_mainland_direct_covers_domestic_ai_model_providers() {
  local rules_file="$ROOT_DIR/rules/MainlandDirect.list"
  local required_rules=(
    "DOMAIN-SUFFIX,deepseek.com"
    "DOMAIN-SUFFIX,doubao.com"
    "DOMAIN-SUFFIX,doubao.com.cn"
    "DOMAIN-SUFFIX,doubao.cn"
    "DOMAIN-SUFFIX,volcengine.com"
    "DOMAIN-SUFFIX,volces.com"
    "DOMAIN-SUFFIX,moonshot.cn"
    "DOMAIN-SUFFIX,moonshot.ai"
    "DOMAIN-SUFFIX,kimi.com"
    "DOMAIN-SUFFIX,qwen.ai"
    "DOMAIN-SUFFIX,dashscope.aliyuncs.com"
    "DOMAIN-SUFFIX,maas.aliyuncs.com"
    "DOMAIN-SUFFIX,hf-mirror.com"
  )

  for rule in "${required_rules[@]}"; do
    grep -qxF "$rule" "$rules_file" || fail "MainlandDirect rules missing domestic AI provider: $rule"
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
test_proxyip_best_generator_allows_country_specific_limits
test_subconverter_group_order_and_pool_names
test_tracked_csv_node_labels_are_ascii_safe
test_polymarket_rules_cover_core_api_domains
test_polymarket_rules_are_inlined_in_subconverter_configs
test_twitter_rules_cover_core_domains
test_twitter_rules_are_referenced_in_subconverter_configs
test_steam_rules_cover_core_store_community_and_cdn_domains
test_steam_rules_are_referenced_in_subconverter_configs
test_mainland_direct_covers_domestic_ai_model_providers

printf 'Linux script tests passed.\n'
