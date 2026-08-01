# Expand TCP Precheck Candidate Pool

## Goal

Broaden the set of new Cloudflare candidates considered by the TCP precheck while reducing the number that proceeds to CloudflareSpeedTest (CFST) per country/source/port.

## Configuration changes

Apply the following defaults in both the Windows PowerShell runner and the Linux shell runner:

| Setting | Current | New |
| --- | ---: | ---: |
| `IpZipSamplePercent` / `IP_ZIP_SAMPLE_PERCENT` | 20 | 40 |
| `IpZipCountryMinCandidates` / `IP_ZIP_COUNTRY_MIN_CANDIDATES` | 20 | 40 |
| `IpZipCountryMaxCandidates` / `IP_ZIP_COUNTRY_MAX_CANDIDATES` | 160 | 320 |
| `CfBestIpPerCountryLimit` / `CF_BESTIP_PER_COUNTRY_LIMIT` | 200 | 400 |
| `Vps789CtLimit` / `VPS789_CT_LIMIT` | 50 | 100 |
| `TcpPrecheckMaxCandidates` / `TCP_PRECHECK_MAX_CANDIDATES` | 80 | 30 |

## Behavior

1. Candidate collection receives the doubled limits above. Existing country-specific sampling multipliers still apply after the base `ip.zip` sampling percentage is doubled.
2. When a work item has more than the existing TCP-precheck threshold, the runner probes new candidates using TCP connect timing.
3. The precheck keeps at most 30 successful new candidates for every `country + source + port` group, ordered by TCP connect time ascending. It retains historical (`previous`) candidates regardless of that cap.
4. CFST continues to perform its existing latency/loss screen and downloads only its latency-prioritized queue according to the unchanged `-dn`, `-dt`, and speed-threshold settings.
5. Final CSV filtering, rolling replacement, and publication limits remain unchanged.

## Error handling

If TCP precheck fails, either runner must retain its current fallback of passing the original candidate list to CFST. A normal precheck that finds no successful new candidates must still preserve historical candidates.

## Verification

Update the Windows and Linux script tests to assert the new default values and to exercise the per-group cap of 30. Run both platform test wrappers after the changes.
