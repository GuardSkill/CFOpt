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
  grep -q '🇭🇰 HK \[北京测速#01 ip.zip\]' "$tmp_dir/work/CloudflareSpeedTest.csv" || fail "generated CSV city should include HK flag"
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

test_runner_defaults_include_europe_focus_countries() {
  grep -q 'COUNTRIES_CSV="${COUNTRIES_CSV:-HK,JP,KR,SG,PH,VN,MY,KZ,MN,IE,US,DE,GB,NL,IT}"' "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" \
    || fail "Linux runner default Countries should include DE/GB/NL/IT"
  grep -q 'FOCUS_COUNTRIES_CSV="${FOCUS_COUNTRIES_CSV:-SG,HK,JP,KR,DE,GB}"' "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" \
    || fail "Linux runner default FocusCountries should include SG/HK/JP/KR/DE/GB"
  grep -q '\[string\[\]\]\$Countries = @("HK", "JP", "KR", "SG", "PH", "VN", "MY", "KZ", "MN", "IE", "US", "DE", "GB", "NL", "IT")' "$ROOT_DIR/scripts/windows/Invoke-CFOptAutoPush.ps1" \
    || fail "Windows runner default Countries should include DE/GB/NL/IT"
  grep -q '\[string\]\$FocusCountries = "SG,HK,JP,KR,DE,GB"' "$ROOT_DIR/scripts/windows/Invoke-CFOptAutoPush.ps1" \
    || fail "Windows runner default FocusCountries should include SG/HK/JP/KR/DE/GB"
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
  for config in "$ROOT_DIR/CFOpt_Subconverter.ini" "$ROOT_DIR/CFOpt_Subconverter_lite.ini"; do
    python3 - "$config" <<'PY'
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
    "Region",
    "Asia Pool",
    "Europe Pool",
    "🇩🇪 Germany Entry + 🇮🇪 IE Proxy",
    "🇩🇪 Germany Entry + 🇦🇹 AT Proxy",
    "🇬🇧 United Kingdom Entry + 🇮🇪 IE Proxy",
    "🇭🇰 Hong Kong Pool",
    "🇯🇵 Japan Pool",
    "🇰🇷 Korea Pool",
    "🇸🇬 Singapore Pool",
    "🇵🇭 Philippines Pool",
    "🇻🇳 Vietnam Pool",
    "🇲🇾 Malaysia Pool",
    "🇰🇿 Kazakhstan Pool",
    "🇲🇳 Mongolia Pool",
    "🇺🇸 United States Pool",
    "🇮🇪 Ireland Pool",
    "🇩🇪 Germany Pool",
    "🇬🇧 United Kingdom Pool",
    "🇳🇱 Netherlands Pool",
    "🇮🇹 Italy Pool",
    "CT Pool",
    "Domain Pool",
]

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

for required in [
    "custom_proxy_group=Proxy`select`[]CodeAgent`[]Region`[]Auto`[]Fallback`[]DIRECT`.*",
    "custom_proxy_group=Region`select`[]Asia Pool`[]Europe Pool`[]🇺🇸 United States Pool",
]:
    if required not in text:
        raise SystemExit(f"{path}: missing simplified routing group: {required}")

for required in [
    "custom_proxy_group=🇩🇪 Germany Entry + 🇮🇪 IE Proxy`url-test`^(🇩🇪|🇮🇪) DE → 🇮🇪 IE \\[",
    "custom_proxy_group=🇩🇪 Germany Entry + 🇦🇹 AT Proxy`url-test`^(🇩🇪|🇦🇹) DE → 🇦🇹 AT \\[",
    "custom_proxy_group=🇬🇧 United Kingdom Entry + 🇮🇪 IE Proxy`url-test`^🇬🇧 GB → 🇮🇪 IE \\[",
    "custom_proxy_group=🇭🇰 Hong Kong Pool`url-test`^🇭🇰 HK ↪ \\[",
    "custom_proxy_group=🇯🇵 Japan Pool`url-test`^🇯🇵 JP ↪ \\[",
    "custom_proxy_group=🇰🇷 Korea Pool`url-test`^🇰🇷 KR ↪ \\[",
    "custom_proxy_group=🇸🇬 Singapore Pool`url-test`^🇸🇬 SG ↪ \\[",
    "custom_proxy_group=🇵🇭 Philippines Pool`url-test`^🇵🇭 PH ↪ \\[",
    "custom_proxy_group=🇻🇳 Vietnam Pool`url-test`^🇻🇳 VN ↪ \\[",
    "custom_proxy_group=🇲🇾 Malaysia Pool`url-test`^🇲🇾 MY ↪ \\[",
    "custom_proxy_group=🇰🇿 Kazakhstan Pool`url-test`^🇰🇿 KZ ↪ \\[",
    "custom_proxy_group=🇲🇳 Mongolia Pool`url-test`^🇲🇳 MN ↪ \\[",
    "custom_proxy_group=🇺🇸 United States Pool`url-test`^🇺🇸 US ↪ \\[",
    "custom_proxy_group=🇮🇪 Ireland Pool`url-test`^🇮🇪 IE ↪ \\[",
    "custom_proxy_group=🇩🇪 Germany Pool`url-test`^🇩🇪 DE ↪ \\[",
    "custom_proxy_group=🇬🇧 United Kingdom Pool`url-test`^🇬🇧 GB ↪ \\[",
    "custom_proxy_group=🇳🇱 Netherlands Pool`url-test`^🇳🇱 NL ↪ \\[",
    "custom_proxy_group=🇮🇹 Italy Pool`url-test`^🇮🇹 IT ↪ \\[",
]:
    if required not in text:
        raise SystemExit(f"{path}: missing proxyip-only pool matcher: {required}")

for forbidden in [
    "custom_proxy_group=🇭🇰 Hong Kong Pool`url-test`^HK",
    "custom_proxy_group=🇯🇵 Japan Pool`url-test`^JP",
    "custom_proxy_group=🇰🇷 Korea Pool`url-test`^KR",
    "custom_proxy_group=🇸🇬 Singapore Pool`url-test`^SG",
    "custom_proxy_group=Asia Pool`url-test`[]🇭🇰 Hong Kong Pool`[]🇯🇵 Japan Pool`[]🇰🇷 Korea Pool`[]🇸🇬 Singapore Pool`^(PH|VN|MY|KZ|MN)",
    "LB-20min",
    "custom_proxy_group=Final",
]:
    if forbidden in text:
        raise SystemExit(f"{path}: ordinary nodes still match a proxyip pool: {forbidden}")
PY
  done
}

test_cfst_log_prefix_handles_scopes
test_linux_defaults_are_not_overly_strict_for_local_runs
test_linux_runner_samples_large_country_files
test_linux_runner_excludes_focus_countries_from_all_scope
test_runner_defaults_include_europe_focus_countries
test_runners_default_to_four_hour_interval
test_focus_scopes_use_quick_download_screening
test_proxyip_best_generator_ranks_candidates_by_tcp_latency
test_subconverter_group_order_and_pool_names

printf 'Linux script tests passed.\n'
