# Country-specific CFST download-speed floors

## Goal

Apply strict, configurable download-speed floors to the JP, US, KR, HK, DE,
GB, and SG test groups on both Windows and Linux. The comparison uses CFST's raw
`download speed (MB/s)` CSV value, not the existing global Mbps conversion.

Default floors:

| Test group | Minimum download speed |
| --- | ---: |
| JP | 10 MB/s |
| US | 5 MB/s |
| KR | 3 MB/s |
| HK | 2 MB/s |
| DE | 5 MB/s |
| GB | 3 MB/s |
| SG | 5 MB/s |

The boundary is inclusive: a result exactly equal to its floor is retained.
For each configured country, the fastest two otherwise-valid unique IPs are
protected before the floor is applied. The third and later IPs must reach the
country floor. If a country has only zero or one otherwise-valid unique IP, it
contributes exactly the available number. Previous and new nodes are treated
identically and compete only on the current run's measured speed.

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
CountryMinSpeedMBPerSec = "JP=10,US=5,KR=3,HK=2,DE=5,GB=3,SG=5"
```

Linux adds an environment variable:

```text
COUNTRY_MIN_SPEED_MB_PER_SEC="JP=10,US=5,KR=3,HK=2,DE=5,GB=3,SG=5"
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
written raw results, after the IP-to-country map has resolved the test group,
and after duplicate IP measurements have been collapsed to the best valid
measurement. Within each configured country, rows are ordered by raw download
speed. The first two rows are protected, and the floor is applied only to the
remaining rows. Floors are not passed through CFST's global `-sl` option
because one CFST invocation cannot express different floors for different
countries.

For each configured country, the merge log reports candidate rows evaluated,
rows protected as the fastest available two, rows removed by the country
floor, and rows retained. Rolling replacement and per-country caps run only on
the protected-or-passing rows, so source preference cannot reintroduce a slower
third-or-later row that failed the current measurement.

## Failure and empty-result behavior

- A configured country with fewer than two otherwise-valid unique IPs emits
  only the available rows and does not fail the complete run.
- The complete run still fails if all countries/groups are filtered out, as it
  does today.
- Missing or unparsable CFST speed values continue to be removed.
- Invalid threshold configuration fails before any CFST work begins.

## Final CSV city label

Every retained row uses its measured CFST download speed in the final CSV
`city` field instead of exposing the candidate source. The format is:

```text
DE [CD#01 13.1MB/s]
```

This applies to every country and every candidate source on Windows and Linux.
The display value is rounded to one decimal place using the same parsed raw
CFST `download speed (MB/s)` value that is written to the row's download-speed
column. The download-speed column retains its existing precision. Source labels
such as `previous`, `ip.zip`, `cf-bestip`, and `vps789` are not emitted in the
final city field. Rows with missing, non-finite, or unparsable speed values are
removed before labeling and therefore cannot produce an empty speed label.

## Tests

Windows and Linux script tests will cover:

1. Default configuration and US inclusion in the focus-country list.
2. Parsing and normalization of the threshold map.
3. A speed below the country floor being removed.
4. A speed exactly equal to the floor being retained.
5. A speed above the floor being retained.
6. Previous and new nodes competing equally on current measured speed.
7. A configured country protecting its fastest two rows even when both are
   below the floor, while filtering a below-floor third row.
8. Unconfigured countries retaining the existing global-floor behavior.
9. Invalid configuration failing before benchmark execution.
10. Effective all/focus CFST arguments remaining `-t 2 -dn 10 -dt 4` and
    single-process execution remaining the default.
11. The default map includes DE at 5 MB/s, GB at 3 MB/s, and SG at 5 MB/s on
    both platforms.
12. Every final city label contains the row's speed rounded to one decimal
    place and no source label, with matching Windows and Linux output.
13. Countries with zero or one otherwise-valid unique IP emit only the rows
    available without failing the complete run.

## Documentation

The README's Windows and Linux parameter sections will document the defaults,
MB/s units, inclusive boundary, fastest-two protection, fewer-than-two
behavior, US focus scope, and examples for overriding or disabling the map.
