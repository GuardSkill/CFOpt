# CodeAgent US Proxy Pool Design

## Goal

Add a United States ProxyIP pool to CodeAgent and maintain US candidates with the same focused benchmarking and publishing lifecycle as JP, HK, KR, and SG.

## Subscription Configuration

- Define `US Proxy ↪` as a `url-test` group matching US ProxyIP chain nodes.
- Use `https://chatgpt.com/backend-api/codex` with the existing 3600-second interval and 50 ms tolerance.
- Add `US Proxy ↪` to the CodeAgent and top-level Proxy selectors after the existing four Asian CodeAgent pools.
- Keep the generic `US Pool` unchanged for non-ProxyIP country routing.

## ProxyIP Maintenance

- Add US to the focused-country defaults in both Windows and Linux runners.
- Ensure the generated `proxyip-best.txt` retains a per-country US allocation using the existing default limit unless an explicit country limit overrides it.
- Include US in all focused candidate preparation, TCP precheck, CFST download test, rolling retest, and CSV publication paths.

## Tests

- Extend Subconverter tests to require the US CodeAgent group and its Codex-backend target in all three configurations.
- Extend Windows and Linux script tests to verify US is a focused country and preserved in ProxyIP best-list defaults.
- Preserve existing country labels, limits, and behavior for all non-US pools.

## Out of Scope

- Changing the shared `US Pool` to include ProxyIP chain nodes.
- Increasing the default number of retained nodes for any existing country.
- Adding credentials or authenticated traffic to url-test probes.
