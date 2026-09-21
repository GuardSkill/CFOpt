#!/usr/bin/env python3
"""Probe small, country-agnostic Cloudflare candidate pools before CFST."""

import argparse
import concurrent.futures
import ipaddress
import json
import re
import socket
import sys
import time
import urllib.request
from datetime import date


SOURCES = {
    "cm": "https://cf.090227.xyz/cmcc",
    "as13335": "https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS13335",
    "as209242": "https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS209242",
}


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "CFOpt-candidate-pool/1.0"})
    with urllib.request.urlopen(request, timeout=25) as response:
        return response.read().decode("utf-8")


def sampled_ips(source, content, max_prefixes, day):
    if source == "cm":
        result = []
        for line in content.splitlines():
            candidate = line.split("#", 1)[0].strip()
            try:
                ip = ipaddress.ip_address(candidate)
            except ValueError:
                continue
            if isinstance(ip, ipaddress.IPv4Address) and ip.is_global:
                result.append(str(ip))
        return list(dict.fromkeys(result))[:max_prefixes]

    prefixes = []
    for entry in json.loads(content)["data"]["prefixes"]:
        try:
            network = ipaddress.ip_network(entry["prefix"], strict=False)
        except (KeyError, ValueError):
            continue
        if isinstance(network, ipaddress.IPv4Network) and network.network_address.is_global:
            prefixes.append(network)
    prefixes = sorted(set(prefixes), key=lambda network: (int(network.network_address), network.prefixlen))
    if len(prefixes) > max_prefixes:
        prefixes = [prefixes[index * len(prefixes) // max_prefixes] for index in range(max_prefixes)]
    return list(dict.fromkeys(
        str(network.network_address + (1 + day % (network.num_addresses - 2) if network.num_addresses > 2 else day % network.num_addresses))
        for network in prefixes
    ))


def tcp_latency(ip, port, timeout):
    started = time.monotonic()
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return (time.monotonic() - started) * 1000
    except (OSError, TimeoutError):
        return None


def select_candidates(sources, ports, max_prefixes, top, timeout, threads, day):
    result = []
    for source in sources:
        try:
            ips = sampled_ips(source, fetch(SOURCES[source]), max_prefixes, day)
        except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
            print(f"WARN: generic {source} source unavailable: {exc}", file=sys.stderr)
            continue
        print(f"Generic {source}: sampled {len(ips)} IPv4 candidates", file=sys.stderr)
        for port in ports:
            with concurrent.futures.ThreadPoolExecutor(max_workers=threads) as executor:
                timings = list(executor.map(lambda ip: tcp_latency(ip, port, timeout), ips))
            ranked = sorted(
                ((milliseconds, ip) for ip, milliseconds in zip(ips, timings) if milliseconds is not None),
                key=lambda item: (item[0], item[1]),
            )
            for _, ip in ranked[:top]:
                result.append((ip, port, f"generic-{source}"))
            print(f"Generic {source} port {port}: connected={len(ranked)} selected={min(top, len(ranked))}", file=sys.stderr)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ports", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--max-prefixes", type=int, default=96)
    parser.add_argument("--top-per-source", type=int, default=128)
    parser.add_argument("--timeout", type=float, default=0.8)
    parser.add_argument("--threads", type=int, default=64)
    args = parser.parse_args()
    ports = [int(port) for port in re.split(r"[,\s]+", args.ports.strip())]
    if not ports or any(port < 1 or port > 65535 for port in ports) or not (1 <= args.max_prefixes <= 512) or not (1 <= args.top_per_source <= 512) or not (0 < args.timeout <= 5) or not (1 <= args.threads <= 128):
        parser.error("invalid port or pool limits")
    rows = select_candidates(SOURCES, ports, args.max_prefixes, args.top_per_source, args.timeout, args.threads, date.today().timetuple().tm_yday)
    with open(args.output, "w", encoding="ascii", newline="\n") as output:
        for ip, port, source in rows:
            output.write(f"{ip},{port},{source}\n")


if __name__ == "__main__":
    main()
