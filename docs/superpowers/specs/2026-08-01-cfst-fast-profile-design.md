# CFST Fast Profile Design

## Goal

Reduce a typical CFOpt benchmark cycle from roughly 56 minutes to about 16--20 minutes while preserving nearly all of the best observed download performance.

## Evidence

- The current raw CFST work-item CSVs contain 266 rows. The script-level second filter removed zero of them because CFST already applied the same latency, loss, and speed thresholds.
- Large all-scope jobs with `-dn 30 -dt 15` took about 320--393 seconds. Focus jobs with `-dn 12 -dt 8` commonly took about 100--165 seconds.
- Replaying work items with at least 12 downloaded candidates shows that downloading the ten lowest-latency candidates retains the absolute fastest candidate in 72.7% of jobs. Its selected best speed averages 99.3% of the original best, with a 97% worst case.
- Reducing the download set to six candidates retains the absolute fastest candidate in only 45.5% of jobs. Average selected best speed falls to 86.4%, with a 16.5% worst case.

## Default Profile

Windows and Linux use the same defaults for all and focus work items:

- CFST latency test count: `2` (`-t 2`).
- CFST download test count: `10` (`-dn 10`).
- CFST maximum download test time: `4` seconds (`-dt 4`).

The existing configuration parameters remain available. `CfstDownloadTestCount` / `CFST_DOWNLOAD_TEST_COUNT` and `CfstDownloadTestTime` / `CFST_DOWNLOAD_TEST_TIME` control all-scope jobs. Focus-specific settings remain supported and default to the same values, allowing later independent tuning without another structural change.

## Unchanged Safety Layers

- Local TCP precheck remains enabled with its existing defaults.
- Previous published nodes continue to bypass TCP precheck and enter CFST.
- CFST keeps enforcing maximum latency, zero loss, and minimum speed.
- Script-level second filtering remains as a low-cost defensive boundary even though it removed zero rows in the inspected run.
- CSV ranking, rolling replacement, per-city limits, and publishing are unchanged.

## Platform and Encoding Requirements

- Windows and Linux expose matching defaults.
- Windows parameter and test changes use ASCII-only literals; no new localized strings are introduced in the runner.
- Installer/scheduled-task paths rely on runner defaults and require no new dependency.

## Testing

- Existing runner tests must expect `-t 2`, `-dn 10`, and `-dt 4` for both all and focus work items.
- Dry-run output tests verify the exact effective CFST arguments.
- Existing TCP precheck, candidate selection, CSV filtering, Windows ASCII, and orchestration tests remain green.

## Expected Performance

The observed run had a 2,800-second maximum download-test budget. Applying a ten-candidate, four-second profile reduces the corresponding budget substantially while retaining the measured 99.3% average best-speed ratio. Together with two rather than six TCPing attempts, the expected total cycle is approximately 16--20 minutes. This is an estimate; normal run logs remain the source of truth after deployment.
