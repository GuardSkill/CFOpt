# TCP Precheck Design

## Goal

Reduce CloudflareSpeedTest (CFST) work by quickly discarding unreachable or slow new candidates from the local Windows and Linux probe hosts, without changing the final definition of a publishable node.

## Scope

- Add an optional TCP-connect precheck to both runner scripts.
- Precheck every new candidate for its configured port; `previous` candidates bypass the precheck and always enter CFST.
- Use ASCII-only strings, comments, file names, log fields, and test assertions in the Windows-specific implementation.
- Preserve candidate source/country labels and the existing final CFST filtering and CSV format.

## Configuration

Both runners expose equivalent defaults:

- `TcpPrecheckEnabled` / `TCP_PRECHECK_ENABLED`: enabled.
- `TcpPrecheckMinCandidates` / `TCP_PRECHECK_MIN_CANDIDATES`: 120. A work item at or below this count skips precheck.
- `TcpPrecheckTimeoutMs` / `TCP_PRECHECK_TIMEOUT_MS`: 800.
- `TcpPrecheckThreads` / `TCP_PRECHECK_THREADS`: 128.
- `TcpPrecheckMaxCandidates` / `TCP_PRECHECK_MAX_CANDIDATES`: 80 new candidates kept per country/source group and port.

The group cap protects geographic/source diversity. A connected candidate is ordered by measured TCP connect duration ascending; ties retain the input order. If fewer than the cap connect before timeout, every connected candidate is passed onward. No non-connected new candidate is passed onward when precheck runs.

## Data Flow

1. Existing selection merges `ip.zip`, cf-bestip, optional vps789, and prior CSV candidates.
2. The precheck reads the selected IP list and its source/city mapping.
3. It separates `previous` rows from new rows.
4. If the work item exceeds the threshold, it probes each new `IP:port` locally with the configured timeout and concurrency, groups successful results by city/source, and writes the capped new results.
5. It appends all previous rows, deduplicates IPs while preferring the richer source map, and replaces the work item's selected input file.
6. Existing CFST invocation, parsing, rolling replacement, CSV filtering, and publishing remain unchanged.

## Platform Details

- Linux uses background Bash `/dev/tcp/IP/PORT` probes with a bounded process pool. Its output is tab-separated ASCII fields: IP, elapsed milliseconds, city, source.
- Windows uses `System.Net.Sockets.TcpClient` with `BeginConnect`/`AsyncWaitHandle.WaitOne`, launched as bounded background jobs. It uses the same ASCII tab-separated intermediate format and selection rules.
- Both paths record `TCP precheck input=`, `connected=`, `kept_new=`, `kept_previous=`, and `elapsed_ms=` in the normal run log.
- TCP success is only a coarse admission check. TLS, packet loss, latency, download speed, and final limits remain CFST responsibilities.

## Failure Handling

- If the precheck facility itself cannot execute, the runner logs a warning and falls back to the unmodified candidate list; it must not produce an empty CFST input solely because a helper failed.
- A valid precheck that finds no connected new candidate still passes historical candidates; if none exist, the work item is skipped with an explanatory warning instead of launching CFST with an empty file.

## Testing

- Linux script tests provide a small fake candidate/mapping fixture and verify: below-threshold bypass; highest-speed new candidates retained by group; prior candidates survive a precheck; and the resulting CFST input is non-empty when a prior node exists.
- Windows tests are static contract checks for ASCII-only precheck literals and matching parameters; full network behavior remains covered by the Linux portable runner test fixture.

## Expected Performance

For a work item with 360 new candidates, 80 retained new candidates, and a small prior-node set, CFST download work drops by about 78%. The precheck adds roughly 1--4 seconds for healthy/failed TCP connections at 128-way concurrency, so work items dominated by CFST download testing should typically complete in 30--45% of their previous time. Items with 120 or fewer candidates do not change.
