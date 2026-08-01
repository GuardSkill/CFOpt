# Country-specific CFST Download-speed Floors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Windows and Linux retain JP, US, KR, and HK rows only when the current CFST raw download speed is at least 10, 5, 3, and 2 MB/s respectively.

**Architecture:** Parse one validated country-to-MB/s map before benchmark work starts, make US a dedicated focus scope, and apply the per-country floor in the final merge before deduplication or rolling retention. Keep the existing global Mbps floor and the single-process CFST profile unchanged; emit per-country filter counters from the merge stage.

**Tech Stack:** PowerShell 5.1, Bash, POSIX awk, XIU2/CloudflareSpeedTest CSV, existing shell-script test harnesses.

## Global Constraints

- Compare against CFST's raw `download speed (MB/s)` column; do not multiply the country floor by eight.
- Defaults are `JP=10,US=5,KR=3,HK=2` MB/s and comparisons are inclusive (`speed >= floor`).
- A configured country with no passing row outputs zero rows; previous nodes never bypass the floor.
- Country identity comes from the selected-IP city map, not the returned Cloudflare colo.
- Preserve `-t 2 -dn 10 -dt 4`, `MaxParallelCfst=1`, and `MAX_PARALLEL_CFST=1` defaults.
- Preserve the existing global `MinSpeedMbps` / `MIN_SPEED_MBPS` filter for all rows.
- An empty country-floor string disables country-specific floors.
- Invalid configuration must fail before downloads, extraction, TCP precheck, or CFST execution.
- Do not modify unrelated worktree changes or the unrelated CodeAgent plan/test work currently present in the main checkout.

---

### Task 1: Windows configuration, focus scope, and strict merge filter

**Files:**
- Modify: `tests/run-windows-script-tests.ps1`
- Modify: `scripts/windows/Invoke-CFOptAutoPush.ps1`

**Interfaces:**
- Consumes: existing `Write-MergedFilteredCsv -WorkItems <object[]> -PreviousNodeKeys <HashSet[string]>` and each work item's `MapPath`, `CsvPath`, and `Port`.
- Produces: parameter `[string]$CountryMinSpeedMBPerSec`, function `ConvertFrom-CountryMinSpeedMap([string], [string[]]) -> Dictionary[string,double]`, and script dictionary `$countryMinSpeedByCode` used by `Write-MergedFilteredCsv`.

- [ ] **Step 1: Add failing Windows parsing/default tests**

After dot-sourcing the runner in `tests/run-windows-script-tests.ps1`, add assertions equivalent to:

```powershell
if ($FocusCountries -ne "SG,HK,JP,KR,US,DE,GB") {
    throw "US must have a dedicated default focus scope."
}
$floors = ConvertFrom-CountryMinSpeedMap -Value $CountryMinSpeedMBPerSec -AllowedCountries $Countries
if ($floors.Count -ne 4 -or $floors["JP"] -ne 10 -or $floors["US"] -ne 5 -or $floors["KR"] -ne 3 -or $floors["HK"] -ne 2) {
    throw "Unexpected default country speed floors."
}
if ((ConvertFrom-CountryMinSpeedMap -Value "" -AllowedCountries $Countries).Count -ne 0) {
    throw "An empty country speed floor map must disable the feature."
}
foreach ($bad in @("JP", "JP=x", "JP=-1", "JP=1,JP=2", "ZZ=1")) {
    try {
        ConvertFrom-CountryMinSpeedMap -Value $bad -AllowedCountries $Countries | Out-Null
        throw "Invalid map was accepted: $bad"
    } catch {
        if ($_.Exception.Message -eq "Invalid map was accepted: $bad") { throw }
    }
}
```

- [ ] **Step 2: Run the Windows suite and verify the new tests fail**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-windows-script-tests.ps1
```

Expected: FAIL because `CountryMinSpeedMBPerSec` and `ConvertFrom-CountryMinSpeedMap` do not exist and US is absent from the default focus list.

- [ ] **Step 3: Implement Windows configuration parsing before the execution guard**

Add the parameter and update the focus default:

```powershell
[string]$CountryMinSpeedMBPerSec = "JP=10,US=5,KR=3,HK=2",
[string]$FocusCountries = "SG,HK,JP,KR,US,DE,GB",
```

Implement an ASCII-only parser near the other configuration helpers. It must split comma-separated `CC=number` pairs, trim whitespace, uppercase keys, reject duplicates and countries absent from `$Countries`, parse with invariant culture, reject NaN/infinity/negative values, and return a case-insensitive `Dictionary[string,double]`. Initialize it before `if ($env:CFOPT_SOURCE_ONLY -ne "1")`:

```powershell
$countryMinSpeedByCode = ConvertFrom-CountryMinSpeedMap `
    -Value $CountryMinSpeedMBPerSec `
    -AllowedCountries $Countries
```

This placement makes invalid configuration fail before any mutable/network benchmark work and exposes the parser to source-only tests.

- [ ] **Step 4: Add a failing Windows merge-boundary test**

In the test temp directory, create one map/CFST pair containing JP rows at `9.99`, `10.00`, and `11.00` MB/s, an HK row below `2.00`, an unconfigured DE row, and mark the `9.99` JP row as previous. Set global `MinSpeedMbps=0`, call `Write-MergedFilteredCsv`, then assert:

```powershell
$output = Import-Csv -LiteralPath $script:csvPath
if ($output.'IP地址' -contains '203.0.113.9') { throw 'Previous JP row below 10 MB/s bypassed its floor.' }
if ($output.'IP地址' -notcontains '203.0.113.10') { throw 'JP row exactly at 10 MB/s was removed.' }
if ($output.'IP地址' -notcontains '203.0.113.11') { throw 'JP row above 10 MB/s was removed.' }
if ($output | Where-Object { $_.'城市' -like 'HK *' }) { throw 'HK must be allowed to produce zero rows.' }
if ($output.'IP地址' -notcontains '203.0.113.20') { throw 'Unconfigured DE row must retain global-floor behavior.' }
```

Also assert the temp log contains country summaries for JP and HK with evaluated/removed/passed counts.

- [ ] **Step 5: Run the Windows suite and verify the merge test fails**

Run the Windows suite from Step 2.

Expected: FAIL because `Write-MergedFilteredCsv` still accepts the below-floor JP/HK rows.

- [ ] **Step 6: Apply the Windows country floor before candidate insertion**

Inside `Write-MergedFilteredCsv`, initialize counters for every configured key, increment `Evaluated` after resolving `$city` and parsing `$speed`, and reject only when a configured floor exists and `$speed -lt $floor`:

```powershell
if ($countryMinSpeedByCode.ContainsKey($city)) {
    $countrySpeedStats[$city].Evaluated++
    if ($speed -lt $countryMinSpeedByCode[$city]) {
        $countrySpeedStats[$city].Removed++
        $removed++
        continue
    }
    $countrySpeedStats[$city].Passed++
}
```

Log all configured countries after processing, including zero counts:

```text
Country speed floor JP >= 10 MB/s: evaluated=3 removed=1 passed=2.
```

Keep this check before `$candidateRows.Add(...)`, deduplication, rolling replacement, and caps.

- [ ] **Step 7: Run the Windows suite and verify it passes**

Run the Windows suite from Step 2.

Expected: `Windows script tests passed.`

- [ ] **Step 8: Commit the Windows behavior**

```powershell
git add scripts/windows/Invoke-CFOptAutoPush.ps1 tests/run-windows-script-tests.ps1
git commit -m "feat: enforce windows country speed floors"
```

---

### Task 2: Linux configuration, focus scope, and strict merge filter

**Files:**
- Modify: `tests/run-linux-script-tests.sh`
- Modify: `scripts/linux/invoke-cfopt-auto-push-linux.sh`

**Interfaces:**
- Consumes: `COMBINED_CANDIDATES_PATH` rows shaped as `port,city,source,<CFST columns>` and existing `filter_csv`.
- Produces: environment variable `COUNTRY_MIN_SPEED_MB_PER_SEC`, normalized variable `COUNTRY_MIN_SPEED_MB_PER_SEC_NORMALIZED`, function `normalize_country_min_speed_map`, and an awk threshold map used by `filter_csv`.

- [ ] **Step 1: Add failing Linux default/parser tests**

Add a test function that source-loads the runner and checks:

```bash
[[ "$FOCUS_COUNTRIES_CSV" == "SG,HK,JP,KR,US,DE,GB" ]] || fail "US must be a default focus country"
[[ "$COUNTRY_MIN_SPEED_MB_PER_SEC" == "JP=10,US=5,KR=3,HK=2" ]] || fail "unexpected country floors"
[[ "$(normalize_country_min_speed_map 'jp=10, US=5' 'HK,JP,US')" == 'JP=10,US=5' ]] || fail "country floor normalization failed"
[[ -z "$(normalize_country_min_speed_map '' 'HK,JP,US')" ]] || fail "empty map must disable floors"
```

For each invalid value `JP`, `JP=x`, `JP=-1`, `JP=1,JP=2`, and `ZZ=1`, assert the parser returns nonzero. Ensure the test restores any environment values it changes.

- [ ] **Step 2: Run the Linux suite and verify the new tests fail**

Run:

```powershell
wsl bash -lc "cd /mnt/h/Projects/CFOpt && bash tests/run-linux-script-tests.sh"
```

Expected: FAIL because the new variable/parser do not exist and US is absent from the default focus list.

- [ ] **Step 3: Implement Linux normalization and early validation**

Add defaults:

```bash
COUNTRY_MIN_SPEED_MB_PER_SEC="${COUNTRY_MIN_SPEED_MB_PER_SEC-JP=10,US=5,KR=3,HK=2}"
FOCUS_COUNTRIES_CSV="${FOCUS_COUNTRIES_CSV:-SG,HK,JP,KR,US,DE,GB}"
```

Implement `normalize_country_min_speed_map VALUE ALLOWED_COUNTRIES` using awk. It must trim fields, uppercase two-letter keys, verify membership in `COUNTRIES_CSV`, reject duplicates, and accept only finite non-negative decimal syntax (`0`, `10`, `10.5`, `.5`). Return normalized `CC=value` pairs in input order. Compute:

```bash
COUNTRY_MIN_SPEED_MB_PER_SEC_NORMALIZED="$(normalize_country_min_speed_map "$COUNTRY_MIN_SPEED_MB_PER_SEC" "$COUNTRIES_CSV")" || {
  log "ERROR: Invalid COUNTRY_MIN_SPEED_MB_PER_SEC: $COUNTRY_MIN_SPEED_MB_PER_SEC"
  exit 1
}
```

Perform this before the main guard calls downloads/extraction/CFST, while keeping source-only tests able to call the function directly.

- [ ] **Step 4: Add a failing Linux end-to-end filtering test**

Create a test-local CFST stub that emits mapped JP speeds `9.99`, `10.00`, and `11.00`, HK `1.99`, and DE `0.10` MB/s. Run the Linux runner with one port, `MIN_SPEED_MBPS=0`, `COUNTRY_MIN_SPEED_MB_PER_SEC='JP=10,HK=2'`, uploads disabled, and deterministic tiny inputs. Assert:

```bash
grep -q '^203\.0\.113\.10,' "$tmp_dir/work/CloudflareSpeedTest.csv" || fail "JP boundary row must survive"
grep -q '^203\.0\.113\.11,' "$tmp_dir/work/CloudflareSpeedTest.csv" || fail "JP above-floor row must survive"
! grep -q '^203\.0\.113\.9,' "$tmp_dir/work/CloudflareSpeedTest.csv" || fail "JP below-floor row survived"
! grep -q ',HK \[' "$tmp_dir/work/CloudflareSpeedTest.csv" || fail "HK should produce zero rows"
grep -q '^203\.0\.113\.20,' "$tmp_dir/work/CloudflareSpeedTest.csv" || fail "DE should retain global behavior"
grep -q 'Country speed floor JP >= 10 MB/s: evaluated=3 removed=1 passed=2.' "$tmp_dir/work/auto-push.log" || fail "missing JP floor stats"
```

Include a previous-node fixture for the `9.99` JP address to prove rolling retention cannot restore it.

- [ ] **Step 5: Run the Linux suite and verify the filtering test fails**

Run the Linux suite from Step 2.

Expected: FAIL because `filter_csv` has no country-specific raw-MB/s check.

- [ ] **Step 6: Apply the Linux threshold inside awk before dedupe state**

Pass the normalized map and a temp stats path into awk:

```bash
-v country_speed_floors="$COUNTRY_MIN_SPEED_MB_PER_SEC_NORMALIZED" \
-v country_speed_stats_path="$WORK_DIR/country-speed-floor-stats.csv"
```

In `BEGIN`, split the map into `country_floor[code]`. After resolving `city` and numeric `speed`, increment configured-country counters and reject when `speed < country_floor[city]`. Only passing rows may populate `best_row`. In `END`, emit one stats line for every configured key, including zero evaluations. After awk succeeds, read the stats file and call `log` with the same message format as Windows.

- [ ] **Step 7: Run syntax and Linux tests**

Run:

```powershell
wsl bash -lc "cd /mnt/h/Projects/CFOpt && bash -n scripts/linux/invoke-cfopt-auto-push-linux.sh && bash tests/run-linux-script-tests.sh"
```

Expected: syntax check exits 0 and the suite prints `Linux script tests passed.`

- [ ] **Step 8: Commit the Linux behavior**

```powershell
git add scripts/linux/invoke-cfopt-auto-push-linux.sh tests/run-linux-script-tests.sh
git commit -m "feat: enforce linux country speed floors"
```

---

### Task 3: Document configuration and operating implications

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the exact Windows/Linux names and semantics implemented in Tasks 1-2.
- Produces: operator documentation for defaults, units, boundary behavior, disabling, overrides, focus scope, and bandwidth concurrency.

- [ ] **Step 1: Add README assertions to the existing runner-default test**

Extend the Linux test harness's static documentation checks to require all of these strings or equivalent wording in both Chinese and English sections:

```text
JP=10,US=5,KR=3,HK=2
COUNTRY_MIN_SPEED_MB_PER_SEC
CountryMinSpeedMBPerSec
MB/s
greater than or equal
```

The Chinese section must explicitly state `大于等于` and that zero qualifying rows means zero output rows.

- [ ] **Step 2: Run the Linux suite and verify the documentation assertion fails**

Run the Linux suite from Task 2.

Expected: FAIL because README has not documented the new controls.

- [ ] **Step 3: Update Chinese and English README sections**

Document:

```powershell
# Override Windows floors
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CountryMinSpeedMBPerSec "JP=12,US=6,KR=4,HK=3"

# Disable Windows country floors
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\Invoke-CFOptAutoPush.ps1" -Force -CountryMinSpeedMBPerSec ""
```

```bash
# Override Linux floors
FORCE=1 COUNTRY_MIN_SPEED_MB_PER_SEC='JP=12,US=6,KR=4,HK=3' ./scripts/linux/invoke-cfopt-auto-push-linux.sh

# Disable Linux country floors
FORCE=1 COUNTRY_MIN_SPEED_MB_PER_SEC='' ./scripts/linux/invoke-cfopt-auto-push-linux.sh
```

Explain that units are CFST raw MB/s, equality passes, a country may output zero rows, US is independently benchmarked, and the default single CFST process avoids saturating an approximately 80 MB/s access link.

- [ ] **Step 4: Run both suites and verify documentation plus behavior**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-windows-script-tests.ps1
wsl bash -lc "cd /mnt/h/Projects/CFOpt && bash tests/run-linux-script-tests.sh"
```

Expected: both suites pass.

- [ ] **Step 5: Commit documentation**

```powershell
git add README.md tests/run-linux-script-tests.sh
git commit -m "docs: explain country speed floor controls"
```

---

### Task 4: Cross-platform final verification and review

**Files:**
- Verify: `scripts/windows/Invoke-CFOptAutoPush.ps1`
- Verify: `scripts/linux/invoke-cfopt-auto-push-linux.sh`
- Verify: `tests/run-windows-script-tests.ps1`
- Verify: `tests/run-linux-script-tests.sh`
- Verify: `README.md`

**Interfaces:**
- Consumes: all behavior from Tasks 1-3.
- Produces: a review-ready branch with fresh cross-platform evidence.

- [ ] **Step 1: Run PowerShell parser validation**

```powershell
$errorsFound = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path '.\scripts\windows\Invoke-CFOptAutoPush.ps1'),
    [ref]$null,
    [ref]$errorsFound
) | Out-Null
if ($errorsFound.Count -gt 0) { $errorsFound; exit 1 }
```

Expected: exit 0 with no parser errors.

- [ ] **Step 2: Run the full Windows and Linux suites**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-windows-script-tests.ps1
wsl bash -lc "cd /mnt/h/Projects/CFOpt && bash -n scripts/linux/invoke-cfopt-auto-push-linux.sh && bash tests/run-linux-script-tests.sh"
```

Expected: both suites pass. The known WSL `D:\CUDA` path-translation warning is non-fatal.

- [ ] **Step 3: Verify the effective defaults without running a real benchmark**

Use Windows source-only loading and Linux source-only loading to assert:

```text
Focus countries: SG,HK,JP,KR,US,DE,GB
Country floors: JP=10,US=5,KR=3,HK=2
CFST profile: -t 2 -dn 10 -dt 4
Maximum parallel CFST jobs: 1
```

Expected: both platforms report identical semantics.

- [ ] **Step 4: Check repository hygiene**

```powershell
git diff --check
git status --short
git log --oneline --decorate -8
```

Expected: no whitespace errors and only intentional feature files differ from the base. Explicitly exclude unrelated CodeAgent changes from every feature commit.

- [ ] **Step 5: Request code review**

Review against `docs/superpowers/specs/2026-08-01-country-download-speed-floors-design.md`, with special attention to raw MB/s versus Mbps, inclusive boundaries, early validation, zero-row countries, old-node bypass, and Windows/Linux parity. Address actionable findings with focused tests before integration.
