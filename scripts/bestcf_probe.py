#!/usr/bin/env python3
"""Confirm CF colo/country and measure download speed through each candidate IP."""

import argparse
import csv
import http.client
import ipaddress
import json
import pathlib
import socket
import ssl
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed

from adaptive_pool import COLO_COUNTRY


class DirectHTTPSConnection(http.client.HTTPSConnection):
    """Connect to the candidate IP while retaining the BestCF hostname for TLS."""

    def __init__(self, ip, host, port, timeout):
        super().__init__(host, port, timeout=timeout)
        self.candidate_ip = ip

    def connect(self):
        # Resolving the per-IP wildcard hostname can block outside Python's
        # socket timeout on Windows. The hostname encodes the destination IP,
        # so connect to that IP directly and use the hostname only as TLS SNI.
        raw_socket = socket.create_connection(
            (self.candidate_ip, self.port), self.timeout, self.source_address
        )
        if self._tunnel_host:
            self.sock = raw_socket
            self._tunnel()
        self.sock = self._context.wrap_socket(raw_socket, server_hostname=self.host)


def candidate_host(ip, suffix):
    address = ipaddress.ip_address(ip)
    if isinstance(address, ipaddress.IPv4Address):
        label = "".join(f"{part:02X}" for part in address.packed)
    else:
        label = address.compressed.replace(":", "-")
    return f"{label}.{suffix}"


def classify_exception(error):
    if isinstance(error, (TimeoutError, socket.timeout)):
        return "timeout"
    if isinstance(error, ssl.SSLError):
        return "tls_error"
    if isinstance(error, socket.gaierror):
        return "dns_error"
    return "connect_error"


def request_identity(ip, port, suffix, timeout):
    host = candidate_host(ip, suffix)
    connection = DirectHTTPSConnection(ip, host, port, timeout)
    started = time.monotonic()
    try:
        connection.request("GET", f"/ip.json?_t={time.time_ns()}", headers={"Cache-Control": "no-cache"})
        response = connection.getresponse()
        payload = response.read(1024 * 1024)
        latency_ms = max(1, round((time.monotonic() - started) * 1000))
        if response.status != 200:
            return None, latency_ms, response.status, "identity_http_error", f"HTTP {response.status}"
        try:
            data = json.loads(payload.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            return None, latency_ms, response.status, "identity_invalid_json", str(error)
        return data, latency_ms, response.status, "ok", ""
    except Exception as error:  # Network failures are data, not fatal script errors.
        return None, 0, 0, f"identity_{classify_exception(error)}", str(error)
    finally:
        connection.close()


def request_download(ip, port, suffix, byte_count, duration, timeout):
    host = candidate_host(ip, suffix)
    connection = DirectHTTPSConnection(ip, host, port, timeout)
    total = 0
    started = time.monotonic()
    http_status = 0
    try:
        connection.request("GET", f"/__down?bytes={byte_count}&_t={time.time_ns()}", headers={"Cache-Control": "no-cache"})
        response = connection.getresponse()
        http_status = response.status
        if response.status != 200:
            response.read(4096)
            return 0.0, total, time.monotonic() - started, http_status, "http_error", f"HTTP {response.status}"
        while True:
            remaining = duration - (time.monotonic() - started)
            if remaining <= 0:
                break
            if connection.sock:
                connection.sock.settimeout(max(0.2, min(timeout, remaining)))
            try:
                chunk = response.read1(64 * 1024)
            except (TimeoutError, socket.timeout):
                if total:
                    break
                raise
            if not chunk:
                break
            total += len(chunk)
        elapsed = max(0.001, time.monotonic() - started)
        if not total:
            return 0.0, total, elapsed, http_status, "no_data", "HTTP 200 returned no body bytes"
        return total / elapsed / 1_000_000, total, elapsed, http_status, "ok", ""
    except Exception as error:  # Network failures are recorded in the sidecar.
        elapsed = max(0.001, time.monotonic() - started)
        if total:
            return total / elapsed / 1_000_000, total, elapsed, http_status, "ok", ""
        return 0.0, total, elapsed, http_status, classify_exception(error), str(error)
    finally:
        connection.close()


def parse_floors(value):
    floors = {}
    for item in (value or "").split(","):
        if "=" not in item:
            continue
        country, floor = item.split("=", 1)
        try:
            floors[country.strip().upper()] = max(0.0, float(floor))
        except ValueError:
            continue
    return floors


def probe(row, expected_country, args, floors):
    ip = row[0].strip()
    identity, identity_latency, identity_http, identity_status, identity_error = request_identity(
        ip, args.port, args.host_suffix, args.timeout
    )
    colo = ""
    country = ""
    if identity:
        colo = str(identity.get("colo") or "").strip().upper()
        country = COLO_COUNTRY.get(colo, "") or str(identity.get("country") or "").strip().upper()

    speed, downloaded, elapsed, download_http, download_status, download_error = request_download(
        ip, args.port, args.host_suffix, args.download_bytes, args.duration, args.timeout
    )
    status = download_status
    error = download_error
    if identity_status != "ok":
        status = identity_status if download_status == "ok" else f"{identity_status}+{download_status}"
        error = "; ".join(part for part in (identity_error, download_error) if part)
    elif download_status == "ok":
        required_mb = max(args.min_speed_mbps / 8.0, floors.get(country or expected_country, 0.0))
        if speed < required_mb:
            status = "low_speed"

    return {
        "ip": ip,
        "speed": speed,
        "colo": colo,
        "country": country,
        "expected_country": expected_country,
        "identity_latency_ms": identity_latency,
        "identity_http": identity_http,
        "download_http": download_http,
        "downloaded": downloaded,
        "elapsed": elapsed,
        "status": status,
        "error": error,
    }


def read_map(path):
    rows = []
    countries = {}
    if not path.is_file():
        return rows, countries
    with path.open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.reader(stream):
            if len(row) < 2:
                continue
            rows.append(row)
            countries.setdefault(row[0].strip(), row[1].strip().upper())
    return rows, countries


def eligible_rows(rows, limit):
    candidates = []
    for index, row in enumerate(rows):
        if len(row) < 6:
            continue
        try:
            received, loss, latency = float(row[2]), float(row[3]), float(row[4])
            ipaddress.ip_address(row[0].strip())
        except (ValueError, TypeError):
            continue
        if received >= 1 and loss < 1 and latency >= 0:
            candidates.append((latency, row[0].strip(), index, row))
    return [item[3] for item in sorted(candidates)[:limit]]


def write_diagnostics(path, results, port, scope):
    path.parent.mkdir(parents=True, exist_ok=True)
    write_header = not path.exists() or path.stat().st_size == 0
    with path.open("a", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        if write_header:
            writer.writerow(("Scope", "IP", "Port", "Status", "IdentityHTTP", "DownloadHTTP", "Error", "ExpectedCountry", "ConfirmedCountry", "ConfirmedColo", "IdentityLatencyMs", "DownloadBytes", "ElapsedSeconds", "SpeedMBps"))
        for result in results:
            writer.writerow((scope, result["ip"], port, result["status"], result["identity_http"], result["download_http"], result["error"], result["expected_country"], result["country"], result["colo"], result["identity_latency_ms"], result["downloaded"], f'{result["elapsed"]:.3f}', f'{result["speed"]:.6f}'))


def run(args):
    csv_path = pathlib.Path(args.csv)
    map_path = pathlib.Path(args.map)
    diagnostics_path = pathlib.Path(args.diagnostics)
    with csv_path.open(encoding="utf-8-sig", newline="") as stream:
        csv_rows = list(csv.reader(stream))
    if not csv_rows:
        return Counter()
    header, rows = csv_rows[0], csv_rows[1:]
    map_rows, expected_countries = read_map(map_path)
    targets = eligible_rows(rows, args.limit)
    floors = parse_floors(args.country_speed_floors)
    results = []
    with ThreadPoolExecutor(max_workers=min(args.concurrency, max(1, len(targets)))) as executor:
        futures = {
            executor.submit(probe, row, expected_countries.get(row[0].strip(), ""), args, floors): row[0].strip()
            for row in targets
        }
        for future in as_completed(futures):
            results.append(future.result())
    by_ip = {result["ip"]: result for result in results}
    for row in rows:
        result = by_ip.get(row[0].strip()) if row else None
        if not result:
            continue
        identity_confirmed = bool(result["country"] and result["colo"] and not result["status"].startswith("identity_"))
        if not identity_confirmed:
            # A candidate that cannot answer /ip.json has not proven its final
            # CF route. Keep it in diagnostics, but make it ineligible for the
            # publication fallback instead of silently trusting its source tag.
            if len(row) > 2:
                row[2] = "0"
            if len(row) > 3:
                row[3] = "1.00"
        if len(row) > 5:
            row[5] = f'{result["speed"]:.2f}' if identity_confirmed and result["status"] in ("ok", "low_speed") else "0.00"
        if len(row) > 6 and result["colo"]:
            row[6] = result["colo"]
    with csv_path.open("w", encoding="utf-8-sig", newline="") as stream:
        csv.writer(stream).writerows([header, *rows])

    if map_rows:
        for row in map_rows:
            result = by_ip.get(row[0].strip())
            if result and result["country"]:
                row[1] = result["country"]
        with map_path.open("w", encoding="ascii", newline="") as stream:
            csv.writer(stream, lineterminator="\n").writerows(map_rows)

    ordered = sorted(results, key=lambda item: item["ip"])
    write_diagnostics(diagnostics_path, ordered, args.port, args.scope)
    counts = Counter(result["status"] for result in results)
    mismatches = sum(
        1 for result in results
        if len(result["expected_country"]) == 2 and result["country"] and result["expected_country"] != result["country"]
    )
    unconfirmed = sum(1 for result in results if not result["country"] or not result["colo"])
    if mismatches:
        counts["country_mismatch"] = mismatches
    if unconfirmed:
        counts["country_unconfirmed"] = unconfirmed
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", required=True)
    parser.add_argument("--map", required=True)
    parser.add_argument("--diagnostics", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--scope", default="")
    parser.add_argument("--limit", type=int, default=15)
    parser.add_argument("--duration", type=float, default=4)
    parser.add_argument("--download-bytes", type=int, default=20_000_000)
    parser.add_argument("--timeout", type=float, default=8)
    parser.add_argument("--concurrency", type=int, default=4)
    parser.add_argument("--host-suffix", default="bestcf.cmliussss.hidns.vip")
    parser.add_argument("--min-speed-mbps", type=float, default=0.03)
    parser.add_argument("--country-speed-floors", default="")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535 or not 1 <= args.limit <= 10000 or not 1 <= args.concurrency <= 32:
        parser.error("invalid port, limit, or concurrency")
    counts = run(args)
    summary = " ".join(f"{key}={counts[key]}" for key in sorted(counts)) or "no_candidates=0"
    print(f"BestCF probe {args.port}/{args.scope}: {summary}")


if __name__ == "__main__":
    main()
