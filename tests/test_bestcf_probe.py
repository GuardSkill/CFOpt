import argparse
import csv
import importlib.util
import pathlib
import socket
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "bestcf_probe.py"
sys.path.insert(0, str(SCRIPT.parent))
spec = importlib.util.spec_from_file_location("bestcf_probe", SCRIPT)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class BestCfProbeTests(unittest.TestCase):
    def test_candidate_host_encodes_ipv4_like_edge_tunnel(self):
        self.assertEqual(
            probe.candidate_host("103.31.4.1", "bestcf.example"),
            "671F0401.bestcf.example",
        )

    def test_direct_https_connection_bypasses_wildcard_dns_but_keeps_sni(self):
        raw_socket = mock.Mock()
        tls_socket = mock.Mock()
        context = mock.Mock()
        context.wrap_socket.return_value = tls_socket
        connection = probe.DirectHTTPSConnection(
            "203.0.113.9", "CB007109.bestcf.example", 8443, 3
        )
        connection._context = context
        with mock.patch.object(socket, "create_connection", return_value=raw_socket) as connect:
            connection.connect()
        connect.assert_called_once_with(("203.0.113.9", 8443), 3, None)
        context.wrap_socket.assert_called_once_with(
            raw_socket, server_hostname="CB007109.bestcf.example"
        )
        self.assertIs(connection.sock, tls_socket)

    def test_probe_distinguishes_http_failure_timeout_and_low_speed(self):
        args = argparse.Namespace(
            port=443,
            host_suffix="bestcf.example",
            timeout=2,
            download_bytes=20_000_000,
            duration=4,
            min_speed_mbps=0.03,
        )
        row = ["203.0.113.1", "2", "2", "0", "10", "0", "N/A"]
        identity = ({"colo": "NRT", "country": "JP"}, 12, 200, "ok", "")
        cases = [
            ((0.5, 2_000_000, 4.0, 200, "ok", ""), "low_speed"),
            ((0.0, 0, 0.2, 403, "http_error", "HTTP 403"), "http_error"),
            ((0.0, 0, 4.0, 0, "timeout", "timed out"), "timeout"),
        ]
        for download, expected in cases:
            with self.subTest(expected=expected), \
                    mock.patch.object(probe, "request_identity", return_value=identity), \
                    mock.patch.object(probe, "request_download", return_value=download):
                result = probe.probe(row, "JP", args, {"JP": 10})
                self.assertEqual(result["status"], expected)
                self.assertEqual(result["country"], "JP")
                self.assertEqual(result["colo"], "NRT")

    def test_run_updates_only_latency_top_limit_and_rewrites_country(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            csv_path = base / "cfst.csv"
            map_path = base / "map.csv"
            diagnostics = base / "diagnostics.csv"
            with csv_path.open("w", encoding="utf-8", newline="") as stream:
                csv.writer(stream).writerows([
                    ["IP", "Sent", "Received", "Loss", "Latency", "Speed", "Colo"],
                    ["203.0.113.2", "2", "2", "0", "20", "0", "N/A"],
                    ["203.0.113.1", "2", "2", "0", "10", "0", "N/A"],
                ])
            map_path.write_text("203.0.113.1,UNKNOWN,generic-test\n203.0.113.2,US,ip.zip\n", encoding="ascii")
            args = argparse.Namespace(
                csv=str(csv_path), map=str(map_path), diagnostics=str(diagnostics),
                port=443, scope="focus-JP", limit=1, duration=4,
                download_bytes=20_000_000, timeout=8, concurrency=1,
                host_suffix="bestcf.example", min_speed_mbps=0.03,
                country_speed_floors="JP=10",
            )
            result = {
                "ip": "203.0.113.1", "speed": 12.5, "colo": "NRT", "country": "JP",
                "expected_country": "UNKNOWN", "identity_latency_ms": 15,
                "identity_http": 200, "download_http": 200, "downloaded": 20_000_000,
                "elapsed": 1.6, "status": "ok", "error": "",
            }
            with mock.patch.object(probe, "probe", return_value=result):
                counts = probe.run(args)
            self.assertEqual(counts["ok"], 1)
            with csv_path.open(encoding="utf-8-sig", newline="") as stream:
                rows = list(csv.reader(stream))
            self.assertEqual(rows[2][5:], ["12.50", "NRT"])
            self.assertEqual(rows[1][5:], ["0", "N/A"])
            self.assertIn("203.0.113.1,JP,generic-test", map_path.read_text(encoding="ascii"))
            self.assertIn("ConfirmedCountry", diagnostics.read_text(encoding="utf-8"))

    def test_unconfirmed_identity_is_not_eligible_for_publication_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            csv_path, map_path, diagnostics = base / "cfst.csv", base / "map.csv", base / "diag.csv"
            csv_path.write_text("IP,Sent,Received,Loss,Latency,Speed,Colo\n203.0.113.8,2,2,0,10,0,N/A\n", encoding="utf-8")
            map_path.write_text("203.0.113.8,JP,ip.zip\n", encoding="ascii")
            args = argparse.Namespace(
                csv=str(csv_path), map=str(map_path), diagnostics=str(diagnostics), port=443,
                scope="focus-JP", limit=1, duration=4, download_bytes=20_000_000,
                timeout=8, concurrency=1, host_suffix="bestcf.example", min_speed_mbps=0.03,
                country_speed_floors="JP=10",
            )
            failed = {
                "ip": "203.0.113.8", "speed": 0.0, "colo": "", "country": "",
                "expected_country": "JP", "identity_latency_ms": 0, "identity_http": 403,
                "download_http": 403, "downloaded": 0, "elapsed": 0.1,
                "status": "identity_http_error+http_error", "error": "HTTP 403",
            }
            with mock.patch.object(probe, "probe", return_value=failed):
                probe.run(args)
            with csv_path.open(encoding="utf-8-sig", newline="") as stream:
                row = list(csv.reader(stream))[1]
            self.assertEqual(row[2:4], ["0", "1.00"])
            self.assertEqual(row[5], "0.00")


if __name__ == "__main__":
    unittest.main()
