# Windows paired probe endpoints

## Selection and failure handling

Windows runs now check endpoint health before downloading candidate pools or
launching the full benchmark. The ordered registry is
`config/probe-endpoints.json`: BestCF, Cloudflare Speed, then three community
fallbacks. Health checking connects directly to reference IPs with TLS
certificate verification, verifies identity, and requires HTTP 200 with at
least 16 KiB of actual download payload. HTML/JSON error pages and redirects
are not accepted as successful downloads. HTTP proxy environment variables
are not used by these socket connections; OS/router-level routing still applies.

Exactly one paired identity/download profile is selected for the whole run.
The channel HTTPing URL and the Python identity/download probe use that profile.
There is no per-node provider switching, because different SNI hostnames can
send the same candidate to different Cloudflare colos. Trace `loc` is the
client's country, not the destination country: the destination is mapped from
`colo`. Unknown colos are rejected rather than guessed from `loc`.

If all profiles fail, selection is deleted and the run stops before full
benchmarking/publication. A healthy preflight does not guarantee every port or
candidate will work later; publication retention protection remains unchanged.
Probe traffic is byte- and time-bounded, including fixed-size download files.

Override with `-ProbeEndpointProvider cloudflare-speed` (or `bestcf`, `7rs`,
`down2`, `netwet`). Use `-ProbeEndpointRegistry` for a different ordered JSON
registry and `-ProbeEndpointReferences` for additional known candidate IPs.
Custom legacy BestCF URLs should be expressed as a complete registry profile
so identity and download configuration remain paired.

## Community fallback candidates checked on 2026-10-27

Source: public endpoint contributions in the upstream
[CloudflareSpeedTest discussion #490](https://github.com/XIU2/CloudflareSpeedTest/discussions/490).
The upstream [README](https://github.com/XIU2/CloudflareSpeedTest#readme)
also explains that the test hostname must be compatible with the target CDN/IP.

| Profile | Host | Download path |
| --- | --- | --- |
| `7rs` | `w.7rs.net` | `/speedtest/?bytes={bytes}` |
| `down2` | `down2.178965.xyz` | `/download/100MB.zip` |
| `netwet` | `testfileorg.netwet.net` | `/500MB-CZIPtestfile.org.zip` |

All three passed direct socket identity and bounded download checks on two
Cloudflare-compatible candidate IPs, followed by the integrated health selector.
These are **reachable from this Chengdu Telecom connection**, not claims of
mainland hosting, operator identity, SLA, or independent failure domains.
The public services may change or disappear; every run rechecks them.
Only small bounded probes were made; large public files are not downloaded in full.

Other candidates were rejected during testing due to TLS errors, 403, or 404;
in particular `w.7rs.net/speedtest/50MiB.test` was 404, while the dynamic
`/speedtest/?bytes=...` path worked. Merely returning `/cdn-cgi/trace` is not
enough to qualify a download endpoint.

## Diagnostics

The work directory contains `probe-endpoint-health.json`,
`selected-probe-endpoint.json`, `bestcf-probe-diagnostics.csv`, and the normal
CSV/log outputs. The Windows workflow uploads an artifact even after failure,
with a seven-day retention period, before Actions cleans its temporary files.
Diagnostics include endpoint/candidate IPs and routes; review them before sharing.
No personal access token is stored in these files.

This change enables automatic provider selection for the Windows script.
The Linux script retains its existing provider behavior; the shared Python
probe remains backward-compatible when no profile is supplied.
