# CodeAgent Backend Probe Design

## Goal

Make CodeAgent's regional automatic proxy groups choose nodes using the Codex backend response latency rather than Anthropic API latency.

## Scope

- Update the `JP Proxy ↪`, `HK Proxy ↪`, `KR Proxy ↪`, and `SG Proxy ↪` CodeAgent groups in all three `CFOpt_Subconverter*.ini` configurations.
- Use `https://chatgpt.com/backend-api/codex` as the url-test target.
- Preserve each group's country/ProxyIP-node filter, 3600-second test interval, and 50 ms tolerance.
- Extend the existing Subconverter configuration regression test to require the Codex backend target for these shared CodeAgent groups.

## Behavior

The probe reaches the Codex service base used by the installed client without an authenticated session. It does not invoke a model, expose credentials, or measure model-generation throughput. Actual model latency remains dependent on the selected model, account load, prompt size, and OpenAI service conditions.

## Out of Scope

- Adding login credentials, API keys, or headers to generated subscriptions.
- Sending authenticated or billable requests for health checking.
- Altering non-CodeAgent service pools, ProxyIP candidate selection, or benchmark CSVs.
