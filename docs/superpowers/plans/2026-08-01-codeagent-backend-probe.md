# CodeAgent Backend Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make CodeAgent's regional automatic groups probe the live Codex backend service base.

**Architecture:** Keep membership, intervals, and tolerances unchanged. Replace only the url-test target in the four shared CodeAgent groups in each Subconverter configuration, then assert that invariant in the existing configuration test.

**Tech Stack:** Subconverter INI configuration; Bash/Python embedded regression checks.

## Global Constraints

- Use `https://chatgpt.com/backend-api/codex` for CodeAgent probes.
- Do not add credentials, headers, or billable API calls.
- Do not change non-CodeAgent groups.

---

### Task 1: Protect and update CodeAgent probe targets

**Files:**

- Modify: `tests/run-linux-script-tests.sh:553-603`
- Modify: `CFOpt_Subconverter.ini:65-68`
- Modify: `CFOpt_Subconverter_lite.ini:37-40`
- Modify: `CFOpt_Subconverter_lite_cmliussss.ini:37-40`

**Interfaces:**

- Consumes: `custom_proxy_group=<country> Proxy ↪` url-test entries.
- Produces: A regression invariant requiring `https://chatgpt.com/backend-api/codex` for the four shared CodeAgent groups.

- [ ] Write a failing test that rejects CodeAgent group targets other than `https://chatgpt.com/backend-api/codex`.
- [ ] Run `bash tests/run-linux-script-tests.sh` and confirm it fails because the groups still reference `https://api.anthropic.com/`.
- [ ] Replace only those four CodeAgent url-test targets in each of the three configurations.
- [ ] Run `bash tests/run-linux-script-tests.sh` and confirm it passes.
- [ ] Commit the configuration, test, and plan changes with message `feat: probe Codex backend for CodeAgent pools`.
