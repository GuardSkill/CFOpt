#!/bin/sh
set -eu

BASE_DIR="${CFOPT_BASE_DIR:-/opt/cfopt}"
REPO_DIR="$BASE_DIR/repo"
WORK_DIR="${CFOPT_WORK_DIR:-/opt/cfopt-work}"
TOKEN_FILE="${CFOPT_TOKEN_FILE:-/etc/cfopt/github-token}"
LOCK_DIR="/tmp/cfopt-openwrt.lock"
ARCHIVE_URL="https://codeload.github.com/GuardSkill/CFOpt/tar.gz/refs/heads/main"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "CFOpt OpenWrt benchmark is already running."
    exit 0
fi
cleanup() {
    rm -rf "$LOCK_DIR"
}
trap cleanup EXIT INT TERM

if [ ! -s "$TOKEN_FILE" ]; then
    echo "Missing GitHub token file: $TOKEN_FILE" >&2
    exit 1
fi
if [ ! -x "$BASE_DIR/bin/cfst" ]; then
    echo "Missing CFST executable: $BASE_DIR/bin/cfst" >&2
    exit 1
fi

mkdir -p "$BASE_DIR" "$WORK_DIR"
archive_path="/tmp/cfopt-main.tar.gz"
new_repo="$BASE_DIR/repo.new"
extract_root="/tmp/cfopt-repo-extract"
rm -rf "$new_repo" "$extract_root" "$archive_path"
mkdir -p "$extract_root"
curl --fail --location --retry 5 --retry-delay 3 --retry-all-errors \
    --output "$archive_path" "$ARCHIVE_URL"
tar -xzf "$archive_path" -C "$extract_root"
extracted_repo=""
for candidate in "$extract_root"/*; do
    if [ -d "$candidate" ]; then
        extracted_repo="$candidate"
        break
    fi
done
test -n "$extracted_repo"
mv "$extracted_repo" "$new_repo"
test -f "$new_repo/scripts/linux/invoke-cfopt-auto-push-linux.sh"
chmod 755 \
    "$new_repo/scripts/linux/invoke-cfopt-auto-push-linux.sh" \
    "$new_repo/scripts/openwrt/setup-cfopt-netns.sh"
rm -rf "$REPO_DIR"
mv "$new_repo" "$REPO_DIR"

"$REPO_DIR/scripts/openwrt/setup-cfopt-netns.sh"

egress="$(ip netns exec cfopt python3 - <<'PY'
import json
import urllib.request

request = urllib.request.Request(
    "https://api.ip.sb/geoip",
    headers={"User-Agent": "CFOpt-OpenWrt"},
)
with urllib.request.urlopen(request, timeout=15) as response:
    payload = json.load(response)
print(" ".join(str(payload.get(key, "")) for key in ("ip", "city", "isp", "asn")))
PY
)"
case "$egress" in
    *Chengdu*China\ Telecom*4134*) ;;
    *)
        echo "Refusing benchmark through unexpected OpenWrt egress: $egress" >&2
        exit 1
        ;;
esac
echo "Verified direct OpenWrt benchmark egress: $egress"

token="$(cat "$TOKEN_FILE")"
ip netns exec cfopt env \
    HOME=/root \
    GITHUB_TOKEN_CFOPT="$token" \
    WORK_DIR="$WORK_DIR" \
    CFST_PATH="$BASE_DIR/bin/cfst" \
    TARGET_PATH=CTC_CD.csv \
    TEST_LOCATION_NAME=CD \
    FORCE=1 \
    CFST_THREADS=32 \
    TCP_PRECHECK_ENABLED=0 \
    BESTCF_PROBE_CONCURRENCY=1 \
    PROXYIP_BEST_WORKERS=24 \
    MAX_PARALLEL_CFST=1 \
    bash "$REPO_DIR/scripts/linux/invoke-cfopt-auto-push-linux.sh"
