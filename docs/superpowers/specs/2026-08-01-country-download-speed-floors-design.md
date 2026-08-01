# Country-specific CFST download-speed floors

## Goal

Apply strict, configurable download-speed floors to the JP, US, KR, and HK
test groups on both Windows and Linux. The comparison uses CFST's raw
`download speed (MB/s)` CSV value, not the existing global Mbps conversion.

Default floors:

| Test group | Minimum download speed |
| --- | ---: |
| JP | 10 MB/s |
| US | 5 MB/s |
| KR | 3 MB/s |
| HK | 2 MB/s |

The boundary is inclusive: a result exactly equal to its floor is retained.
If no result in a configured group reaches its floor, that group contributes
zero rows to the final CSV. Previous nodes do not bypass the floor.

## Scope and group identity

The floor is selected from the candidate's configured country/test group as
recorded in the selected-IP city map. It is not selected from the Cloudflare
colo returned by CFST. For example, a US-group candidate that reaches LAX is
checked against the US floor; a JP-group candidate that happens to reach LAX
is still checked against the JP floor.

US becomes a default focus country on both platforms. This gives US its own
candidate pool and download-test quota instead of making it compete with all
non-focus countries for the ordinary scope's `-dn 10` slots.

## Configuration

Windows adds a string parameter:

```text
CountryMinSpeedMBPerSec = "JP=10,US=5,KR=3,HK=2"
```

Linux adds an environment variable:

```text
COUNTRY_MIN_SPEED_MB_PER_SEC="JP=10,US=5,KR=3,HK=2"
```

Keys are normalized to uppercase. Values must be finite, non-negative decimal
numbers interpreted as MB/s. Duplicate keys, unknown country codes, malformed
pairs, or invalid values fail fast with a clear error rather than silently
weakening filtering. An empty string disables country-specific floors.

The existing global `MinSpeedMbps` / `MIN_SPEED_MBPS` behavior remains in
place for every row. A configured country row must pass both the existing
global floor and its country-specific MB/s floor.

## Runtime behavior

Both runners retain the fast CFST profile:

```text
-t 2 -dn 10 -dt 4
```

Both also retain one CFST process at a time by default:

```text
MaxParallelCfst=1 / MAX_PARALLEL_CFST=1
```

This prevents independent country jobs from competing for the host's roughly
80 MB/s maximum bandwidth. CFST's latency thread count remains 80 because it
does not imply 80 simultaneous downloads.

Country-specific floors are applied during final CSV merging, after CFST has
written raw results and after the IP-to-country map has resolved the test
group. They are not passed through CFST's global `-sl` option because one
CFST invocation cannot express different floors for different countries.

For each configured country, the merge log reports candidate rows evaluated,
rows removed by the country floor, and rows retained after that floor. Normal
deduplication, rolling replacement, and per-country caps run only on rows that
have passed the floor, so an old or otherwise preferred row can never be
reintroduced after failing the current measurement.

## Failure and empty-result behavior

- A configured country with zero qualifying rows is omitted without failing
  the complete run.
- The complete run still fails if all countries/groups are filtered out, as it
  does today.
- Missing or unparsable CFST speed values continue to be removed.
- Invalid threshold configuration fails before any CFST work begins.

## Tests

Windows and Linux script tests will cover:

1. Default configuration and US inclusion in the focus-country list.
2. Parsing and normalization of the threshold map.
3. A speed below the country floor being removed.
4. A speed exactly equal to the floor being retained.
5. A speed above the floor being retained.
6. Previous nodes not bypassing the floor.
7. A configured country legitimately producing zero final rows.
8. Unconfigured countries retaining the existing global-floor behavior.
9. Invalid configuration failing before benchmark execution.
10. Effective all/focus CFST arguments remaining `-t 2 -dn 10 -dt 4` and
    single-process execution remaining the default.

## Documentation

The README's Windows and Linux parameter sections will document the defaults,
MB/s units, inclusive boundary, strict zero-row behavior, US focus scope, and
examples for overriding or disabling the map.
