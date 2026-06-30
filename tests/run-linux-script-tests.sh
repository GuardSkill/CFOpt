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

test_runner_defaults_exclude_europe_focus_countries() {
  grep -q 'COUNTRIES_CSV="${COUNTRIES_CSV:-HK,JP,KR,SG,PH,VN,MY,KZ,MN,IE,US}"' "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" \
    || fail "Linux runner default Countries should exclude DE/GB/NL/IT"
  grep -q 'FOCUS_COUNTRIES_CSV="${FOCUS_COUNTRIES_CSV:-HK,KR,JP,SG}"' "$ROOT_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh" \
    || fail "Linux runner default FocusCountries should exclude DE/GB/NL/IT"
  grep -q '\[string\[\]\]\$Countries = @("HK", "JP", "KR", "SG", "PH", "VN", "MY", "KZ", "MN", "IE", "US")' "$ROOT_DIR/scripts/windows/Invoke-CFOptAutoPush.ps1" \
    || fail "Windows runner default Countries should exclude DE/GB/NL/IT"
  grep -q '\[string\]\$FocusCountries = "HK,KR,JP,SG"' "$ROOT_DIR/scripts/windows/Invoke-CFOptAutoPush.ps1" \
    || fail "Windows runner default FocusCountries should exclude DE/GB/NL/IT"
}

test_cfst_log_prefix_handles_scopes
test_linux_defaults_are_not_overly_strict_for_local_runs
test_linux_runner_samples_large_country_files
test_linux_runner_excludes_focus_countries_from_all_scope
test_runner_defaults_exclude_europe_focus_countries

printf 'Linux script tests passed.\n'
