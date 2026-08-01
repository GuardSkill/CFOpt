# Expand TCP Precheck Pool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Double every configured new-candidate source limit while retaining only the fastest 30 new candidates per country/source/port after TCP precheck.

**Architecture:** Keep the existing candidate collection and TCP-precheck control flow. Change only its platform-default limits and its regression assertions, so CFST latency/download behavior and final publication rules remain unchanged.

**Tech Stack:** PowerShell 5.1, Bash, existing script-test wrappers.

## Global Constraints

- Apply identical defaults to the Windows and Linux runners.
- Preserve historical (`previous`) candidates during TCP precheck.
- Do not change CFST `-dn`, `-dt`, latency, loss, speed, CSV, or publication behavior.

---

### Task 1: Windows runner and regression test

- [x] Add failing assertions for defaults `40,40,320,400,100,30` and a 30-new-plus-one-previous precheck result.
- [x] Run the Windows wrapper and confirm it fails for the old defaults.
- [x] Change the six Windows defaults and fixture expectations.
- [x] Run the Windows wrapper and confirm it passes.

### Task 2: Linux runner and regression test

- [x] Add failing literal-default assertions and change the TCP fixture expectation to 30 new plus one previous.
- [x] Run the Linux wrapper and confirm it fails for the old defaults.
- [x] Change the six Linux defaults and fixture expectations.
- [x] Run the Linux wrapper and confirm it passes.

### Task 3: Combined verification

- [x] Run both complete platform test wrappers.
- [x] Run `git diff --check` and inspect the final diff against the approved design.
