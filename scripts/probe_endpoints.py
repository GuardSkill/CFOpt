#!/usr/bin/env python3
"""Health-check paired Cloudflare identity/download endpoints before a full run.

Connections go to the supplied candidate IPs, not through HTTP proxy settings.
Select ONE provider for the entire run: do not mix colos/speeds from providers.
"""
import argparse
import json
import pathlib
import re
from bestcf_probe import request_identity, request_download


DEFAULT_PROFILES = [
    dict(name="bestcf", host="671F0401.bestcf.cmliussss.hidns.vip",
         identity_path="/ip.json", identity_format="json", download_path="/__down?bytes={bytes}"),
    dict(name="cloudflare-speed", host="speed.cloudflare.com",
         identity_path="/cdn-cgi/trace", identity_format="trace", download_path="/__down?bytes={bytes}"),
]


def validate_profile(profile):
    if not isinstance(profile, dict):
        raise ValueError("Endpoint profile must be an object")
    for key in ("name", "host", "identity_path", "identity_format", "download_path"):
        if not isinstance(profile.get(key), str) or not profile[key]:
            raise ValueError(f"Missing endpoint field: {key}")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]{0,252}", profile["host"]):
        raise ValueError("Endpoint host must be a plain DNS hostname")
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", profile["name"]):
        raise ValueError("Invalid endpoint name")
    if profile["identity_format"] not in ("trace", "json"):
        raise ValueError("Unsupported identity format")
    for key in ("identity_path", "download_path"):
        path = profile[key]
        if not path.startswith("/") or path.startswith("//") or any(ord(c) < 32 for c in path):
            raise ValueError("Endpoint paths must be local absolute HTTP paths")
        if any(c in path for c in ('"', "'", "`", "\\")):
            raise ValueError("Invalid character in endpoint path")
    return dict(profile)


def select_endpoint(profiles, references, timeout=4, check_port=443):
    checks = []
    for profile in profiles:
        profile = validate_profile(profile)
        for ip in references:
            identity, latency, code, status, error = request_identity(ip, check_port, "", timeout, profile)
            check = dict(provider=profile["name"], reference=ip, port=check_port,
                         identity_status=status, identity_http=code, error=error, latency_ms=latency)
            if status == "ok" and identity and identity.get("colo"):
                speed, count, elapsed, download_code, download_status, download_error = request_download(
                    ip, check_port, "", 262144, 1, timeout, profile)
                check.update(download_status=download_status, download_http=download_code,
                             download_bytes=count, speed_MBps=speed, download_error=download_error)
                if download_status == "ok" and count >= 16384:
                    checks.append(check)
                    return profile, checks
            checks.append(check)
    return None, checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", help="JSON array of endpoint profiles in priority order")
    parser.add_argument("--provider", default="auto", help="auto or an explicit registry profile name")
    parser.add_argument("--references", default="104.16.0.1,172.64.0.1,103.31.4.1")
    parser.add_argument("--port", type=int, default=443)
    parser.add_argument("--timeout", type=float, default=4)
    parser.add_argument("--output", required=True)
    parser.add_argument("--diagnostics", required=True)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535 or not 0 < args.timeout <= 60:
        parser.error("Invalid port or timeout")
    output = pathlib.Path(args.output)
    output.unlink(missing_ok=True)  # A failed check must never reuse a stale selection.
    profiles = DEFAULT_PROFILES
    if args.registry:
        profiles = json.loads(pathlib.Path(args.registry).read_text(encoding="utf-8-sig"))
    if not isinstance(profiles, list) or not profiles:
        parser.error("Registry must contain a nonempty profile array")
    profiles = [validate_profile(profile) for profile in profiles]
    if args.provider != "auto":
        profiles = [profile for profile in profiles if profile["name"] == args.provider]
        if not profiles:
            parser.error("Provider is not present in the registry")
    selected, checks = select_endpoint(profiles, [r.strip() for r in args.references.split(",") if r.strip()], args.timeout, args.port)
    diagnostics = pathlib.Path(args.diagnostics)
    diagnostics.parent.mkdir(parents=True, exist_ok=True)
    diagnostics.write_text(json.dumps(dict(selected=selected, checks=checks), indent=2), encoding="utf-8")
    if not selected:
        raise SystemExit("No healthy identity/download endpoint; full benchmark and publication blocked")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(selected, indent=2), encoding="utf-8")
    print(f"Selected paired endpoint: {selected['name']} ({selected['host']}); fixed for this run")


if __name__ == "__main__":
    main()
