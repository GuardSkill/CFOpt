#!/usr/bin/env bash
set -euo pipefail

OWNER="${OWNER:-GuardSkill}"
REPO="${REPO:-CFOpt}"
BRANCH="${BRANCH:-main}"
WORK_DIR="${WORK_DIR:-$HOME/cfopt-auto-push}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/$OWNER/$REPO/$BRANCH}"
SCRIPT_URL="${SCRIPT_URL:-$BASE_URL/scripts/linux/invoke-cfopt-auto-push-linux.sh}"
CFST_URL="${CFST_URL:-$BASE_URL/scripts/linux/cfst}"
CFST_TAR_URL="${CFST_TAR_URL:-$BASE_URL/scripts/linux/cfst_linux_amd64.tar.gz}"
INSTALL_DAILY_AUTORUN="${INSTALL_DAILY_AUTORUN:-1}"
DAILY_AT="${DAILY_AT:-04:00}"
AUTORUN_BACKEND="${AUTORUN_BACKEND:-auto}"
INTERVAL_HOURS="${INTERVAL_HOURS:-4}"
FOCUS_COUNTRIES_CSV="${FOCUS_COUNTRIES_CSV:-SG,HK,JP,KR,DE,GB}"
IPZIP_COUNTRY_SAMPLE_MULTIPLIERS="${IPZIP_COUNTRY_SAMPLE_MULTIPLIERS:-KR=2,US=0.5}"

mkdir -p "$WORK_DIR"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing command: $1" >&2
    exit 1
  fi
}

need_cmd curl

echo "Downloading CFOpt Linux runner to $WORK_DIR"
curl -fL --retry 3 -o "$WORK_DIR/invoke-cfopt-auto-push-linux.sh" "$SCRIPT_URL"
chmod +x "$WORK_DIR/invoke-cfopt-auto-push-linux.sh"

if [[ ! -x "$WORK_DIR/cfst" ]]; then
  echo "Downloading cfst binary"
  if curl -fL --retry 3 -o "$WORK_DIR/cfst" "$CFST_URL"; then
    chmod +x "$WORK_DIR/cfst"
  else
    echo "Direct cfst download failed, trying tar.gz"
    need_cmd tar
    curl -fL --retry 3 -o "$WORK_DIR/cfst_linux_amd64.tar.gz" "$CFST_TAR_URL"
    tar -xzf "$WORK_DIR/cfst_linux_amd64.tar.gz" -C "$WORK_DIR"
    if [[ ! -f "$WORK_DIR/cfst" ]]; then
      found_cfst="$(find "$WORK_DIR" -maxdepth 2 -type f -name cfst | head -n 1 || true)"
      if [[ -n "$found_cfst" ]]; then
        cp "$found_cfst" "$WORK_DIR/cfst"
      fi
    fi
    chmod +x "$WORK_DIR/cfst"
  fi
fi

install_daily_autorun() {
  [[ "$INSTALL_DAILY_AUTORUN" == "1" ]] || return 0

  local runner="$WORK_DIR/invoke-cfopt-auto-push-linux.sh"
  local hour minute
  hour="${DAILY_AT%%:*}"
  minute="${DAILY_AT##*:}"
  local token_line=""
  if [[ -n "${GITHUB_TOKEN_CFOPT:-}" ]]; then
    token_line="Environment=GITHUB_TOKEN_CFOPT=${GITHUB_TOKEN_CFOPT}"
  fi

  if [[ "$AUTORUN_BACKEND" != "cron" ]] && command -v systemctl >/dev/null 2>&1 && systemctl --user status >/dev/null 2>&1; then
    local systemd_dir="$HOME/.config/systemd/user"
    mkdir -p "$systemd_dir"
    cat > "$systemd_dir/cfopt-auto-push.service" <<EOF
[Unit]
Description=CFOpt daily rolling retest and upload

[Service]
Type=oneshot
Environment=WORK_DIR=$WORK_DIR
Environment=CFST_PATH=$WORK_DIR/cfst
Environment=INTERVAL_HOURS=$INTERVAL_HOURS
Environment=FOCUS_COUNTRIES_CSV=$FOCUS_COUNTRIES_CSV
Environment=IPZIP_COUNTRY_SAMPLE_MULTIPLIERS=$IPZIP_COUNTRY_SAMPLE_MULTIPLIERS
$token_line
ExecStart=$runner
EOF

    cat > "$systemd_dir/cfopt-auto-push.timer" <<EOF
[Unit]
Description=Run CFOpt daily

[Timer]
OnCalendar=*-*-* 00/$INTERVAL_HOURS:$minute:00
Persistent=true
Unit=cfopt-auto-push.service

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now cfopt-auto-push.timer
    echo "Installed user systemd timer: cfopt-auto-push.timer (every $INTERVAL_HOURS hours at minute $minute)"
    return 0
  fi

  if [[ "$AUTORUN_BACKEND" != "systemd" ]] && command -v crontab >/dev/null 2>&1; then
    local cron_line
    cron_line="$minute */$INTERVAL_HOURS * * * GITHUB_TOKEN_CFOPT=\"${GITHUB_TOKEN_CFOPT:-}\" WORK_DIR=\"$WORK_DIR\" CFST_PATH=\"$WORK_DIR/cfst\" INTERVAL_HOURS=4 FOCUS_COUNTRIES_CSV=\"SG,HK,JP,KR,DE,GB\" IPZIP_COUNTRY_SAMPLE_MULTIPLIERS=\"KR=2,US=0.5\" \"$runner\" >> \"$WORK_DIR/cron.log\" 2>&1"
    (crontab -l 2>/dev/null | grep -v 'cfopt-auto-push-linux.sh'; echo "$cron_line") | crontab -
    echo "Installed crontab job every $INTERVAL_HOURS hours at minute $minute."
    return 0
  fi

  echo "WARN: systemd user timer and crontab are unavailable. Daily autorun was not installed."
}

install_daily_autorun

echo "Running CFOpt now. Set GITHUB_TOKEN_CFOPT before running if upload is needed."
FORCE="${FORCE:-1}" \
WORK_DIR="$WORK_DIR" \
CFST_PATH="$WORK_DIR/cfst" \
IPZIP_COUNTRY_SAMPLE_MULTIPLIERS="$IPZIP_COUNTRY_SAMPLE_MULTIPLIERS" \
"$WORK_DIR/invoke-cfopt-auto-push-linux.sh"
