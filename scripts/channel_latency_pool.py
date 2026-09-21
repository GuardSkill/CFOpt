#!/usr/bin/env python3
"""Rank every candidate channel by CFST latency before the download-test stage."""

import argparse
import csv
import ipaddress
import os
import pathlib
import subprocess
import sys
from collections import defaultdict

from adaptive_pool import COLO_COUNTRY


def valid_ip(value):
    try:
        return isinstance(ipaddress.ip_address(value), ipaddress.IPv4Address)
    except ValueError:
        return False


def load_work_items(path):
    items = []
    groups = defaultdict(lambda: defaultdict(set))
    with open(path, encoding="utf-8-sig", newline="") as stream:
        for port, scope, selected_path, map_path in csv.reader(stream):
            selected = set(pathlib.Path(selected_path).read_text(encoding="ascii").splitlines())
            mappings = []
            with open(map_path, encoding="ascii", newline="") as mapping_stream:
                for row in csv.reader(mapping_stream):
                    if len(row) < 3 or row[0] not in selected or not valid_ip(row[0]):
                        continue
                    ip, country, source = row[:3]
                    country = country.upper()
                    mappings.append((ip, country, source))
                    if scope != "previous" and source != "previous":
                        groups[(source, int(port))][ip].add(country)
            items.append((int(port), scope, pathlib.Path(selected_path), pathlib.Path(map_path), mappings))
    return items, groups


def add_generic(groups, path):
    if not path or not pathlib.Path(path).is_file():
        return
    with open(path, encoding="ascii", newline="") as stream:
        for row in csv.reader(stream):
            if len(row) != 3 or not valid_ip(row[0]) or not row[1].isdigit() or not row[2].startswith("generic-"):
                continue
            ip, port, source = row
            groups[(source, int(port))][ip].add("UNKNOWN")


def cfst_latency(cfst, workdir, source, port, ips, httping, url, max_latency, latency_tests, timeout, use_proxy=False):
    safe_source = "".join(character if character.isalnum() else "-" for character in source)
    input_path = workdir / f"latency-{safe_source}-{port}.txt"
    output_path = workdir / f"latency-{safe_source}-{port}.csv"
    input_path.write_text("".join(f"{ip}\n" for ip in sorted(ips)), encoding="ascii")
    if output_path.exists():
        output_path.unlink()
    command = [cfst, "-f", str(input_path), "-o", str(output_path), "-dd", "-n", "80", "-t", str(latency_tests), "-tl", str(max_latency), "-tlr", "0", "-p", "0", "-tp", str(port)]
    if httping:
        command.extend(("-httping", "-url", url))
    environment = os.environ.copy()
    if not use_proxy:
        for key in list(environment):
            if key.lower() in ("http_proxy", "https_proxy", "all_proxy", "no_proxy"):
                environment.pop(key)
    try:
        completed = subprocess.run(command, input="\n", text=True, encoding="utf-8", errors="replace", stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=timeout, check=False, env=environment)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"WARN: latency stage {source}/{port} failed: {exc}", file=sys.stderr)
        return None
    if completed.returncode:
        print(f"WARN: latency stage {source}/{port} exited {completed.returncode}: {completed.stderr[-300:]}", file=sys.stderr)
        return None
    if not output_path.exists():
        return []
    with open(output_path, encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.reader(stream))
    return rows[1:]


def rank_channels(groups, run_latency, top):
    qualified = defaultdict(dict)
    fallback = set()
    for (source, port), ips in sorted(groups.items()):
        unknown = any("UNKNOWN" in countries or any(len(country) != 2 for country in countries) for countries in ips.values())
        rows = run_latency(source, port, ips, unknown)
        if rows is None:
            fallback.add((source, port))
            continue
        for row in rows:
            if len(row) < 7 or row[0] not in ips:
                continue
            try:
                latency = float(row[4])
                received = float(row[2])
                loss = float(row[3])
            except ValueError:
                continue
            if received < 1 or loss >= 1 or latency < 0:
                continue
            colo_country = COLO_COUNTRY.get(row[6].strip().upper(), "")
            countries = {colo_country} if colo_country else {country for country in ips[row[0]] if len(country) == 2 and country.isalpha()}
            for country in countries:
                # Generic/unknown inputs need an observed CFST Colo; never invent their country.
                if "UNKNOWN" in ips[row[0]] and not colo_country:
                    continue
                key = (source, country)
                prior = qualified[key].get(row[0])
                candidate = (latency, row[0], port)
                if prior is None or candidate < prior:
                    qualified[key][row[0]] = candidate
        print(f"Latency {source}/{port}: input={len(ips)} valid={len(rows)}", file=sys.stderr)
    selected = set()
    for (source, country), ip_rows in sorted(qualified.items()):
        ranked = sorted(ip_rows.values())[:top]
        selected.update((ip, port, country, source) for _, ip, port in ranked)
        print(f"Channel {source}/{country}: selected={len(ranked)} across all ports", file=sys.stderr)
    return selected, fallback


def rewrite_work_items(items, selected, fallback):
    discovered = defaultdict(list)
    for ip, port, country, source in sorted(selected):
        discovered[(port, country)].append((ip, country, source))
    for port, scope, selected_path, map_path, mappings in items:
        if scope == "previous":
            continue
        # The dedicated CT seed item is discovery-only; its classified winners
        # join country scopes, instead of bypassing the channel/country cap.
        if scope == "ct-entry" and ("ct-pool", port) in fallback:
            continue
        allowed = {scope[6:].upper()} if scope.startswith("focus-") else {country for _, country, _ in mappings if len(country) == 2}
        kept = []
        if scope != "ct-entry":
            for ip, country, source in mappings:
                if (source, port) in fallback or (ip, port, country, source) in selected:
                    kept.append((ip, country, source))
            for country in sorted(allowed):
                kept.extend(discovered[(port, country)])
        seen = set()
        unique = []
        for ip, country, source in kept:
            if ip not in seen:
                unique.append((ip, country, source))
                seen.add(ip)
        selected_temp = selected_path.with_name(selected_path.name + ".latency-tmp")
        map_temp = map_path.with_name(map_path.name + ".latency-tmp")
        selected_temp.write_text("".join(f"{ip}\n" for ip, _, _ in unique), encoding="ascii")
        map_temp.write_text("".join(f"{ip},{country},{source}\n" for ip, country, source in unique), encoding="ascii")
        os.replace(selected_temp, selected_path)
        os.replace(map_temp, map_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-items", required=True)
    parser.add_argument("--generic")
    parser.add_argument("--cfst", required=True)
    parser.add_argument("--workdir", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--max-latency", type=int, default=420)
    parser.add_argument("--latency-tests", type=int, default=2)
    parser.add_argument("--top-per-channel-country", type=int, default=20)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--use-proxy-for-cfst", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.top_per_channel_country <= 100 or not 1 <= args.latency_tests <= 10:
        parser.error("invalid latency-stage limit")
    workdir = pathlib.Path(args.workdir)
    items, groups = load_work_items(args.work_items)
    add_generic(groups, args.generic)
    selected, fallback = rank_channels(groups, lambda source, port, ips, httping: cfst_latency(args.cfst, workdir, source, port, ips, httping, args.url, args.max_latency, args.latency_tests, args.timeout, args.use_proxy_for_cfst), args.top_per_channel_country)
    rewrite_work_items(items, selected, fallback)


if __name__ == "__main__":
    main()
