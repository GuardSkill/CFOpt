# CFST Fast Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change Windows and Linux CFST defaults to two TCPing attempts, ten download candidates, and four seconds per download.

**Architecture:** Keep the existing runner configuration interfaces and orchestration. Change only default values, assert effective dry-run arguments on both platforms, and update operator documentation; TCP precheck and final filtering remain untouched.

**Tech Stack:** Bash, PowerShell, existing shell and PowerShell test harnesses.

## Global Constraints

- Default CFST arguments are `-t 2 -dn 10 -dt 4` for all and focus work items.
- Existing overrides continue to work.
- Windows runner additions and test literals remain ASCII-only.
- TCP precheck, final filtering, rolling replacement, and publishing behavior do not change.

---

### Task 1: Failing cross-platform default tests

**Files:**
- Modify: `tests/run-linux-script-tests.sh`
- Modify: `tests/run-windows-script-tests.ps1`

**Interfaces:**
- Consumes each runner's existing dry-run argument construction.
- Verifies all-scope and focus-scope jobs emit `-t 2 -dn 10 -dt 4`.

- [ ] **Step 1: Add Linux behavior assertions**

Extend a dry-run fixture with both all and focus work items. Assert `auto-push.log` contains `-t 2 -dn 10 -dt 4` for each scope.

- [ ] **Step 2: Add Windows default assertions**

Dot-source the runner with `CFOPT_SOURCE_ONLY=1` and assert `CfstLatencyTestCount`, `CfstDownloadTestCount`, `CfstDownloadTestTime`, `FocusCfstDownloadTestCount`, and `FocusCfstDownloadTestTime` resolve to `2,10,4,10,4`.

- [ ] **Step 3: Verify red state**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-windows-script-tests.ps1`

Run: `wsl -e bash -lc 'cd /mnt/h/Projects/CFOpt && bash tests/run-linux-script-tests.sh'`

Expected: both fail because current defaults are `6,30,15,12,8`.

### Task 2: Minimal runner default changes

**Files:**
- Modify: `scripts/windows/Invoke-CFOptAutoPush.ps1:19-24`
- Modify: `scripts/linux/invoke-cfopt-auto-push-linux.sh:20-26`

**Interfaces:**
- Produces equivalent Windows and Linux default CFST arguments.

- [ ] **Step 1: Change Linux defaults**

Set `CFST_LATENCY_TEST_COUNT=2`, `CFST_DOWNLOAD_TEST_COUNT=10`, `CFST_DOWNLOAD_TEST_TIME=4`, `FOCUS_CFST_DOWNLOAD_TEST_COUNT=10`, and `FOCUS_CFST_DOWNLOAD_TEST_TIME=4` when not overridden.

- [ ] **Step 2: Change Windows defaults**

Set `CfstLatencyTestCount=2`, `CfstDownloadTestCount=10`, `CfstDownloadTestTime=4`, `FocusCfstDownloadTestCount=10`, and `FocusCfstDownloadTestTime=4`.

- [ ] **Step 3: Verify green state**

Run both platform test suites and expect zero failures.

### Task 3: Documentation and final verification

**Files:**
- Modify: `README.md` in Chinese and English parameter sections

- [ ] **Step 1: Document the fast profile**

Replace documented default CFST arguments with `-t 2 -dn 10 -dt 4`; state that all/focus defaults are unified and overrides remain available.

- [ ] **Step 2: Run full verification**

Run Windows tests, Linux tests, PowerShell parser validation, `bash -n`, and `git diff --check`.

- [ ] **Step 3: Commit**

Run: `git add README.md scripts/windows/Invoke-CFOptAutoPush.ps1 scripts/linux/invoke-cfopt-auto-push-linux.sh tests/run-linux-script-tests.sh tests/run-windows-script-tests.ps1 docs/superpowers/plans/2026-08-01-cfst-fast-profile.md && git commit -m "perf: shorten cfst benchmark profile"`
