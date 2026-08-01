#!/usr/bin/env python3
import argparse
import concurrent.futures
import socket
import ssl
import time
import urllib.request
from pathlib import Path
from urllib.parse import urlparse


DEFAULT_COUNTRIES = ("IE", "AT", "AU", "KR", "HK", "SG", "JP", "DE", "GB")


def load_text(source):
    parsed = urlparse(source)
    if parsed.scheme in ("http", "https"):
        request = urllib.request.Request(source, headers={"User-Agent": "CFOptProxyipBest/1.0"})
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read().decode("utf-8-sig")
    if parsed.scheme == "file":
        with urllib.request.urlopen(source, timeout=30) as response:
            return response.read().decode("utf-8-sig")
    return Path(source).read_text(encoding="utf-8-sig")


def parse_source(text, countries):
    country_set = {country.upper() for country in countries}
    pools = {country: [] for country in country_set}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "#" not in line:
            continue
        address, country = line.rsplit("#", 1)
        address = address.strip()
        country = country.strip().upper()
        if country not in country_set or not address:
            continue
        if address not in pools[country]:
            pools[country].append(address)
    return pools


def split_host_port(address):
    value = address.strip()
    default_port = 443
    if value.startswith("[") and "]:" in value:
        host, port = value.rsplit("]:", 1)
        return host + "]", int(port)
    if value.count(":") == 1:
        host, port = value.rsplit(":", 1)
        try:
            return host, int(port)
        except ValueError:
            return value, default_port
    return value, default_port


def probe_one(address, timeout, probe_host):
    host, port = split_host_port(address)
    if host.startswith("[") and host.endswith("]"):
        host = host[1:-1]
    started = time.perf_counter()
    try:
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        with socket.create_connection((host, port), timeout=timeout) as connection:
            connection.settimeout(timeout)
            with context.wrap_socket(connection, server_hostname=probe_host) as tls_connection:
                request = f"HEAD / HTTP/1.1\r\nHost: {probe_host}\r\nConnection: close\r\n\r\n"
                tls_connection.sendall(request.encode("ascii"))
                response = tls_connection.recv(16)
                if response.startswith(b"HTTP/"):
                    return time.perf_counter() - started, address
    except (OSError, ssl.SSLError):
        pass
    return float("inf"), address


def rank_pool(addresses, limit, timeout, workers, probe_host):
    if not addresses:
        return []
    worker_count = max(1, min(workers, len(addresses)))
    with concurrent.futures.ThreadPoolExecutor(max_workers=worker_count) as executor:
        results = list(executor.map(lambda item: probe_one(item, timeout, probe_host), addresses))
    reachable = [item for item in results if item[0] != float("inf")]
    ranked = sorted(reachable, key=lambda item: (item[0], addresses.index(item[1])))
    return [address for _latency, address in ranked[:limit]]


def parse_country_limits(value):
    limits = {}
    for raw_item in (value or "").split(","):
        item = raw_item.strip()
        if not item:
            continue
        if "=" not in item:
            raise argparse.ArgumentTypeError(f"invalid country limit '{item}', expected COUNTRY=LIMIT")
        country, raw_limit = item.split("=", 1)
        country = country.strip().upper()
        if not country:
            raise argparse.ArgumentTypeError(f"invalid country limit '{item}', missing country")
        try:
            limit = int(raw_limit.strip())
        except ValueError as exc:
            raise argparse.ArgumentTypeError(f"invalid country limit '{item}', limit must be an integer") from exc
        if limit < 1:
            raise argparse.ArgumentTypeError(f"invalid country limit '{item}', limit must be >= 1")
        limits[country] = limit
    return limits


def main():
    parser = argparse.ArgumentParser(description="Generate a small per-country proxyip-best.txt from zip.cm.edu.kg all.txt.")
    parser.add_argument("--source", default="https://zip.cm.edu.kg/all.txt")
    parser.add_argument("--output", required=True)
    parser.add_argument("--countries", default=",".join(DEFAULT_COUNTRIES))
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument("--country-limits", default="", help="Comma-separated COUNTRY=LIMIT overrides, for example HK=50.")
    parser.add_argument("--timeout", type=float, default=0.75)
    parser.add_argument("--workers", type=int, default=64)
    parser.add_argument("--probe-host", default="cloudflare.com", help="SNI and Host header used to validate ProxyIP traffic.")
    args = parser.parse_args()

    countries = [item.strip().upper() for item in args.countries.split(",") if item.strip()]
    country_limits = parse_country_limits(args.country_limits)
    pools = parse_source(load_text(args.source), countries)
    lines = []
    for country in countries:
        country_limit = country_limits.get(country, args.limit)
        ranked = rank_pool(pools.get(country, []), max(1, country_limit), args.timeout, args.workers, args.probe_host)
        for address in ranked:
            lines.append(f"{address}#{country}")

    Path(args.output).write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


if __name__ == "__main__":
    main()
