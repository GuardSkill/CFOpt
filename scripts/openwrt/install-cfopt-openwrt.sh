#!/bin/sh
set -eu

SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BASE_DIR="${CFOPT_BASE_DIR:-/opt/cfopt}"
TOKEN_FILE="${CFOPT_TOKEN_FILE:-/etc/cfopt/github-token}"
CRON_SCHEDULE="${CFOPT_CRON_SCHEDULE:-20 4 * * *}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this installer as root." >&2
    exit 1
fi
if [ -z "${GITHUB_TOKEN_CFOPT:-}" ] && [ ! -s "$TOKEN_FILE" ]; then
    echo "Set GITHUB_TOKEN_CFOPT before installation." >&2
    exit 1
fi

apk add kmod-macvlan
mkdir -p "$BASE_DIR/bin" /opt/cfopt-work /etc/cfopt /etc/netns/cfopt
cp "$SOURCE_DIR/cfopt-resolv.conf" /etc/cfopt/resolv.conf
cp "$SOURCE_DIR/cfopt-openwrt-run.sh" /usr/bin/cfopt-openwrt-run
chmod 755 /usr/bin/cfopt-openwrt-run
if [ -n "${GITHUB_TOKEN_CFOPT:-}" ]; then
    umask 077
    printf '%s' "$GITHUB_TOKEN_CFOPT" > "$TOKEN_FILE"
fi
chmod 600 "$TOKEN_FILE"

if [ ! -x "$BASE_DIR/bin/cfst" ]; then
    release_json="/tmp/cfopt-cfst-release.json"
    archive_path="/tmp/cfopt-cfst.tar.gz"
    extract_dir="/tmp/cfopt-cfst-extract"
    curl --fail --location --retry 5 --retry-delay 3 --retry-all-errors \
        --output "$release_json" \
        https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/latest
    asset_url="$(python3 - "$release_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    release = json.load(handle)
matches = [
    asset["browser_download_url"]
    for asset in release.get("assets", [])
    if asset.get("name", "").endswith("linux_amd64.tar.gz")
]
if len(matches) != 1:
    raise SystemExit(f"expected one linux_amd64 CFST asset, found {len(matches)}")
print(matches[0])
PY
)"
    curl --fail --location --retry 5 --retry-delay 3 --retry-all-errors \
        --output "$archive_path" "$asset_url"
    gzip -t "$archive_path"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    tar -xzf "$archive_path" -C "$extract_dir"
    cfst_source="$(find "$extract_dir" -type f -name cfst | head -n 1)"
    test -n "$cfst_source"
    cp "$cfst_source" "$BASE_DIR/bin/cfst"
    chmod 755 "$BASE_DIR/bin/cfst"
fi

cron_tmp="/tmp/cfopt-root-cron"
grep -v 'cfopt-openwrt-run' /etc/crontabs/root 2>/dev/null > "$cron_tmp" || true
printf '%s /usr/bin/cfopt-openwrt-run >>/opt/cfopt-work/cron.log 2>&1\n' \
    "$CRON_SCHEDULE" >> "$cron_tmp"
mv "$cron_tmp" /etc/crontabs/root
/etc/init.d/cron restart

echo "CFOpt OpenWrt runner installed. Schedule: $CRON_SCHEDULE"
