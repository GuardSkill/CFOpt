# TCP Precheck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local TCP prechecks that reduce CFST deep-test inputs without weakening final CSV validation.

**Architecture:** Each runner prechecks only newly sourced candidates after selection and before starting CFST. Previous CSV nodes bypass precheck. Linux uses a portable helper in the runner; Windows uses .NET `TcpClient`; both retain the same grouped fastest candidates and emit ASCII log records.

**Tech Stack:** Bash, PowerShell, .NET `System.Net.Sockets.TcpClient`, existing shell test harness.

## Global Constraints

- Windows additions use ASCII-only strings, comments, file names, logs, and test assertions.
- Default values: enabled; min candidates 120; timeout 800ms; concurrency 128; max new candidates 80 per city/source group and port.
- Previous candidates always pass into CFST unchanged.
- CFST remains the only final verifier of latency, loss, TLS/download behavior, and publication eligibility.

---

### Task 1: Linux failing contracts and configuration

**Files:**
- Modify: `tests/run-linux-script-tests.sh`
- Modify: `scripts/linux/invoke-cfopt-auto-push-linux.sh:5-55`

**Interfaces:**
- Produces environment controls `TCP_PRECHECK_ENABLED`, `TCP_PRECHECK_MIN_CANDIDATES`, `TCP_PRECHECK_TIMEOUT_MS`, `TCP_PRECHECK_THREADS`, and `TCP_PRECHECK_MAX_CANDIDATES`.

- [ ] **Step 1: Write failing tests**

Add a test which runs the Linux runner against a local fixture containing 121 new IP records plus a `previous` record, turns `TCP_PRECHECK_ENABLED=1`, and asserts the runner log contains `TCP precheck input=` and the selected file keeps the previous record. Add static checks for all five defaults.

- [ ] **Step 2: Run tests to verify failure**

Run: `bash tests/run-linux-script-tests.sh`

Expected: FAIL because no TCP precheck defaults or log event exist.

- [ ] **Step 3: Add minimal configuration**

Add the five environment defaults to the Linux runner and route them to the precheck function call site before `start_cfst_for_port`.

- [ ] **Step 4: Run focused test**

Run: `bash tests/run-linux-script-tests.sh`

Expected: the new test still fails only because the precheck function has not been implemented.

### Task 2: Linux TCP precheck implementation

**Files:**
- Modify: `scripts/linux/invoke-cfopt-auto-push-linux.sh` near candidate selection/startup functions
- Test: `tests/run-linux-script-tests.sh`

**Interfaces:**
- Consumes selected-IP files and `ip,city,source` maps created by `build_port_work_item`.
- Produces a replacement selected-IP file with successful capped new nodes plus all prior nodes.

- [ ] **Step 1: Write failing behavior test**

Use a fixture containing a local listening TCP port, one unreachable new address, more than 120 reachable new records distributed across two source/city groups, and one previous address. Assert each group has no more than 80 new entries, unreachable new entries are absent, and the previous address remains.

- [ ] **Step 2: Run test to verify failure**

Run: `bash tests/run-linux-script-tests.sh`

Expected: FAIL because unreachable candidates remain and the group cap is not enforced.

- [ ] **Step 3: Implement minimal precheck**

Implement `apply_tcp_precheck(port, selected_ip_path, map_path)`: split previous/new nodes through the map source; skip under threshold or disabled; probe new nodes using bounded background `/dev/tcp` jobs; write `IP<TAB>elapsed_ms`; rank successful nodes per city/source; cap to the configured limit; append previous nodes and atomically replace input. On helper error, leave original input and log `WARN: TCP precheck failed; using original candidates.`

- [ ] **Step 4: Run test suite**

Run: `bash tests/run-linux-script-tests.sh`

Expected: PASS including existing candidate sampling and CFST orchestration tests.

### Task 3: Windows parity and ASCII contract

**Files:**
- Modify: `scripts/windows/Invoke-CFOptAutoPush.ps1:1-55` and candidate/CFST orchestration functions
- Modify: `tests/run-linux-script-tests.sh`

**Interfaces:**
- Produces parameters `TcpPrecheckEnabled`, `TcpPrecheckMinCandidates`, `TcpPrecheckTimeoutMs`, `TcpPrecheckThreads`, and `TcpPrecheckMaxCandidates` with Linux-equivalent defaults.

- [ ] **Step 1: Write failing static contracts**

Add shell assertions that Windows contains each parameter/default, `System.Net.Sockets.TcpClient`, `TCP precheck input=`, and does not include non-ASCII characters within the newly added `Invoke-TcpPrecheck` function region.

- [ ] **Step 2: Run tests to verify failure**

Run: `bash tests/run-linux-script-tests.sh`

Expected: FAIL because Windows precheck parameters and helper do not exist.

- [ ] **Step 3: Implement Windows precheck**

Add `Invoke-TcpPrecheck` using bounded `Start-Job` workers and `TcpClient.BeginConnect`; wait for each connection for the configured millisecond timeout; gather successful elapsed milliseconds; group/cap new records by city/source; retain all previous records; update selected input only after successful processing. All added literal strings are ASCII.

- [ ] **Step 4: Run test suite**

Run: `bash tests/run-linux-script-tests.sh`

Expected: PASS.

### Task 4: Documentation and verification

**Files:**
- Modify: `README.md` in Chinese and English tuning sections
- Modify: `docs/superpowers/specs/2026-08-01-tcp-precheck-design.md` only if implementation differs from the approved design

- [ ] **Step 1: Write failing documentation contract**

Add test assertions that README mentions `TCP_PRECHECK_ENABLED` and `TcpPrecheckEnabled`.

- [ ] **Step 2: Run test to verify failure**

Run: `bash tests/run-linux-script-tests.sh`

Expected: FAIL because neither option is documented.

- [ ] **Step 3: Document tuning**

Document defaults, historical-node bypass, skip threshold, and an example command for each platform. State that TCP precheck is not final validation.

- [ ] **Step 4: Run complete verification**

Run: `bash tests/run-linux-script-tests.sh; git diff --check; git status --short`

Expected: tests pass, no whitespace errors, and only expected files are modified.

- [ ] **Step 5: Commit**

Run: `git add scripts/windows/Invoke-CFOptAutoPush.ps1 scripts/linux/invoke-cfopt-auto-push-linux.sh tests/run-linux-script-tests.sh README.md docs/superpowers/specs/2026-08-01-tcp-precheck-design.md docs/superpowers/plans/2026-08-01-tcp-precheck.md && git commit -m "feat: precheck tcp candidates before cfst"`
