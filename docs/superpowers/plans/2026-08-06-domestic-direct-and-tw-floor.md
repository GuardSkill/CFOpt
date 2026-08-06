# Domestic Direct Routing and TW Floor Exception Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Direct-route the requested Chinese services and remove the Taiwan download-speed floor.

**Architecture:** Keep service routing centralized in `rules/MainlandDirect.list`, which all three Subconverter configs already route to `Direct`. Remove only the TW item from Windows and Linux country-floor default strings; leave Taiwan in their candidate and focus defaults.

**Tech Stack:** Subconverter INI configuration, Clash rules, PowerShell, Bash.

## Global Constraints

- Do not duplicate service rules in INI files.
- Do not alter non-TW speed floors or TW candidate/focus defaults.
- Do not stage generated `.cfopt-*` directories or Python cache artifacts.

---

### Task 1: Add shared direct-service rules

**Files:**

- Modify: `rules/MainlandDirect.list`
- Modify: `tests/run-linux-script-tests.sh`

**Interfaces:** Every Subconverter configuration already references `rules/MainlandDirect.list` as `Direct`.

- [ ] **Step 1: Write the failing test**

Extend the MainlandDirect required-rule array with exact suffixes for `yuque.com`, `yuque.com.cn`, `yuqueapp.com`, `yuqueapp.cn`, `yuqueusercontent.com`, `zhihu.com`, `zhihu.cn`, `zhimg.com`, and `zhihuishu.com`.

- [ ] **Step 2: Run test to verify it fails**

Run `wsl.exe -e bash -lc 'cd /mnt/h/Projects/CFOpt && bash tests/run-linux-script-tests.sh'`; expected failure is a missing Yuque rule.

- [ ] **Step 3: Write minimal implementation**

Add those exact `DOMAIN-SUFFIX` lines to `rules/MainlandDirect.list` following the existing Youdao section.

- [ ] **Step 4: Run test to verify it passes**

Rerun the Linux test; it must end with `Linux script tests passed.`

### Task 2: Remove Taiwan country speed floor

**Files:**

- Modify: `scripts/windows/Invoke-CFOptAutoPush.ps1`
- Modify: `scripts/linux/invoke-cfopt-auto-push-linux.sh`
- Modify: `tests/run-windows-script-tests.ps1`
- Modify: `tests/run-linux-script-tests.sh`
- Modify: `README.md`

**Interfaces:** The runner defaults use comma-separated `COUNTRY=MB/s` entries.

- [ ] **Step 1: Write the failing tests**

Change default-floor assertions to expect `JP=10,US=5,KR=3,HK=2,DE=5,GB=3,SG=5` and assert the defaults do not contain `TW=`.

- [ ] **Step 2: Run tests to verify they fail**

Run the Windows test with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-windows-script-tests.ps1` and the Linux test command from Task 1. Both should fail because their defaults contain `TW=3`.

- [ ] **Step 3: Write minimal implementation**

Remove `TW=3,` from each runner default. Update Chinese and English README floor documentation to say TW has no country speed floor.

- [ ] **Step 4: Run tests to verify they pass**

Rerun both suites and `git diff --check`; both suites must pass and the diff check must be empty.

- [ ] **Step 5: Commit and push**

Stage only the tracked rule, runner, test, README, specification, and plan files; commit and push `main`.
