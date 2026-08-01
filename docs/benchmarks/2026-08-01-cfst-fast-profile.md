# CFST fast profile benchmark (Windows)

- Date: 2026-08-01 (Asia/Shanghai)
- Host path: `H:\Projects\CFOpt`
- Script: `scripts/windows/Invoke-CFOptAutoPush.ps1 -Force -SkipUpload`
- Effective CFST profile: `-t 2 -dn 10 -dt 4`
- Ports: `443,2053,2083,2087,2096,8443`
- Started: 2026-08-01 12:42:31
- Last CFST result written: 2026-08-01 13:10:13
- Effective benchmark duration: 27 minutes 42 seconds (1,662 seconds)
- Historical full-flow baseline: approximately 56 minutes
- Observed reduction: approximately 28 minutes 18 seconds, or 50.5%

## Result

- Completed CFST work items: 36
- Merged candidate rows kept: 134
- Rows removed by filtering/deduplication/caps: 53
- Final file: `CloudflareSpeedTest_CD.csv`
- Countries/groups present: DE, GB, HK, IT, JP, KR, NL, SG, US
- Latency range: 44.12-385.53 ms
- Download-speed range: 0.03-112.57 MB/s

## Run note

All CFST result CSVs completed successfully. The wrapper process later stalled while
serially consuming a large redirected CFST progress log and was stopped after its
30-minute outer command limit. The repository's existing `Write-MergedFilteredCsv`
function was then invoked against the 36 completed per-scope CSVs and their original
city maps. This recovery did not repeat or replace any measurements.
