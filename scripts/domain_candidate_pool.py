#!/usr/bin/env python3
"""Fetch and rank Cloudflare-backed domain endpoints by /cdn-cgi/trace latency."""

import argparse
import csv
import datetime as dt
import hashlib
import http.client
import pathlib
import re
import ssl
import time
import urllib.request
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed

from adaptive_pool import COLO_COUNTRY


HOST_RE = re.compile(
    r"^(?=.{1,253}\.?$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}\.?$"
)


def parse_domain(line):
    value = line.split("#", 1)[0].strip().lower().rstrip(".")
    if not value:
        return None, None
    port = None
    if value.count(":") == 1:
        host, port_text = value.rsplit(":", 1)
        if port_text.isdigit() and 1 <= int(port_text) <= 65535:
            value, port = host, int(port_text)
    if not HOST_RE.fullmatch(value):
        return None, None
    return value, port


def parse_trace(payload):
    result = {}
    for line in payload.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key.strip()] = value.strip()
    return result


def trace_request(host, port, timeout, context):
    connection = http.client.HTTPSConnection(host, port, timeout=timeout, context=context)
    try:
        started = time.monotonic()
        connection.request(
            "GET",
            f"/cdn-cgi/trace?_t={time.time_ns()}",
            headers={"Cache-Control": "no-cache", "User-Agent": "CFOpt-DomainPool"},
        )
        response = connection.getresponse()
        payload = response.read(64 * 1024).decode("utf-8", "replace")
        elapsed_ms = max(1, round((time.monotonic() - started) * 1000))
        if response.status != 200:
            raise RuntimeError(f"HTTP {response.status}")
        return parse_trace(payload), elapsed_ms
    finally:
        connection.close()


def probe_domain(host, port, timeout, attempts, retries, required_client_country):
    context = ssl.create_default_context()
    identity = None
    for _ in range(max(1, retries + 1)):
        try:
            trace, _ = trace_request(host, port, timeout, context)
            if trace.get("h", "").lower().rstrip(".") != host:
                continue
            if required_client_country and trace.get("loc", "").upper() != required_client_country:
                continue
            colo = trace.get("colo", "").upper()
            country = COLO_COUNTRY.get(colo, "")
            if trace.get("ip") and country:
                identity = (country, colo)
                break
        except Exception:
            continue
    if not identity:
        return None

    samples = []
    for _ in range(max(1, attempts)):
        try:
            trace, elapsed_ms = trace_request(host, port, timeout, context)
            if (
                trace.get("h", "").lower().rstrip(".") == host
                and (not required_client_country or trace.get("loc", "").upper() == required_client_country)
                and COLO_COUNTRY.get(trace.get("colo", "").upper(), "") == identity[0]
            ):
                samples.append(elapsed_ms)
        except Exception:
            continue
    if not samples:
        return None
    return {
        "endpoint": host,
        "port": port,
        "country": identity[0],
        "colo": identity[1],
        "sent": max(1, attempts),
        "received": len(samples),
        "loss": (max(1, attempts) - len(samples)) / max(1, attempts),
        "latency": min(samples),
    }


def choose_port(host, explicit_port, ports, rotation):
    if explicit_port:
        return explicit_port
    digest = hashlib.sha256(f"{rotation}:{host}".encode("utf-8")).digest()
    return ports[int.from_bytes(digest[:4], "big") % len(ports)]


def rank_domains(results, top_per_country, max_latency):
    grouped = defaultdict(list)
    for result in results:
        if result and result["latency"] <= max_latency and result["loss"] < 1:
            grouped[result["country"]].append(result)
    selected = []
    for country in sorted(grouped):
        selected.extend(
            sorted(grouped[country], key=lambda row: (row["latency"], row["endpoint"], row["port"]))[
                :top_per_country
            ]
        )
    return selected


def write_work_items(workdir, selected):
    workdir = pathlib.Path(workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    manifest = workdir / "domain-work-items.csv"
    for old in workdir.glob("domain-bestcf-*"):
        if old.is_file():
            old.unlink()

    grouped = defaultdict(list)
    for row in selected:
        grouped[(row["country"], row["port"])].append(row)

    manifest_rows = []
    for (country, port), rows in sorted(grouped.items()):
        scope = f"domain-{country}"
        stem = workdir / f"domain-bestcf-{country}-{port}"
        selected_path = stem.with_suffix(".txt")
        map_path = pathlib.Path(f"{stem}-map.csv")
        csv_path = workdir / f"CloudflareSpeedTest-{port}-{scope}.csv"
        selected_path.write_text("".join(f'{row["endpoint"]}\n' for row in rows), encoding="ascii")
        with map_path.open("w", encoding="ascii", newline="") as stream:
            writer = csv.writer(stream, lineterminator="\n")
            for row in rows:
                writer.writerow((row["endpoint"], country, "domain-bestcf"))
        with csv_path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream, lineterminator="\n")
            writer.writerow(("IP", "Sent", "Received", "Loss", "Latency", "Speed", "Colo"))
            for row in rows:
                writer.writerow(
                    (
                        row["endpoint"],
                        row["sent"],
                        row["received"],
                        f'{row["loss"]:.2f}',
                        row["latency"],
                        "0",
                        row["colo"],
                    )
                )
        manifest_rows.append((port, scope, selected_path, map_path))

    with manifest.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerows(manifest_rows)
    return manifest_rows


def run(args):
    request = urllib.request.Request(args.url, headers={"User-Agent": "CFOpt-DomainPool"})
    with urllib.request.urlopen(request, timeout=max(10, args.timeout * 4)) as response:
        lines = response.read(2 * 1024 * 1024).decode("utf-8-sig", "replace").splitlines()
    ports = [int(value) for value in args.ports.split(",") if value.strip()]
    if not ports:
        raise ValueError("No domain candidate ports configured")
    rotation = args.rotation or dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")
    candidates = []
    seen = set()
    for line in lines:
        host, explicit_port = parse_domain(line)
        if not host or host in seen:
            continue
        seen.add(host)
        candidates.append((host, choose_port(host, explicit_port, ports, rotation)))

    results = []
    with ThreadPoolExecutor(max_workers=min(args.concurrency, max(1, len(candidates)))) as executor:
        futures = {
            executor.submit(
                probe_domain,
                host,
                port,
                args.timeout,
                args.attempts,
                args.retries,
                args.require_client_country,
            ): (host, port)
            for host, port in candidates
        }
        for future in as_completed(futures):
            result = future.result()
            if result:
                results.append(result)
    selected = rank_domains(results, args.top_per_country, args.max_latency)
    manifest_rows = write_work_items(args.workdir, selected)
    counts = Counter(row["country"] for row in selected)
    print(
        f"Domain candidate pool fetched={len(candidates)} qualified={len(results)} "
        f"selected={len(selected)} top_per_country={args.top_per_country} "
        f"countries={','.join(f'{key}:{counts[key]}' for key in sorted(counts)) or 'none'} "
        f"work_items={len(manifest_rows)}"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--workdir", required=True)
    parser.add_argument("--ports", default="443,2053,2083,2087,2096,8443")
    parser.add_argument("--top-per-country", type=int, default=5)
    parser.add_argument("--max-latency", type=int, default=420)
    parser.add_argument("--timeout", type=float, default=1.5)
    parser.add_argument("--concurrency", type=int, default=32)
    parser.add_argument("--attempts", type=int, default=3)
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--require-client-country", default="CN")
    parser.add_argument("--rotation", default="")
    args = parser.parse_args()
    args.top_per_country = max(1, args.top_per_country)
    args.concurrency = max(1, args.concurrency)
    args.attempts = max(1, args.attempts)
    args.retries = max(0, args.retries)
    run(args)


if __name__ == "__main__":
    main()
