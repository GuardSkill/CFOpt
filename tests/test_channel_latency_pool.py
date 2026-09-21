import importlib.util
import pathlib
import sys
import tempfile
import unittest
from collections import defaultdict
from unittest.mock import patch


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "channel_latency_pool.py"
sys.path.insert(0, str(SCRIPT.parent))
spec = importlib.util.spec_from_file_location("channel_latency_pool", SCRIPT)
pool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pool)


class ChannelLatencyPoolTests(unittest.TestCase):
    def test_top_is_per_channel_and_country_across_ports(self):
        groups = {
            ("ip.zip", 443): {"104.16.0.1": {"JP"}, "104.16.0.2": {"JP"}},
            ("ip.zip", 2053): {"104.16.0.3": {"JP"}},
            ("generic-cm", 443): {"104.17.0.1": {"UNKNOWN"}, "104.17.0.2": {"UNKNOWN"}},
        }
        def latency(source, port, ips, httping):
            if source == "generic-cm":
                self.assertTrue(httping)
                return [
                    ["104.17.0.1", "1", "1", "0", "8", "0", "HKG"],
                    ["104.17.0.2", "1", "1", "0", "1", "0", "N/A"],
                ]
            self.assertFalse(httping)
            return [[ip, "1", "1", "0", str(ms), "0", "N/A"] for ip, ms in
                    (("104.16.0.1", 10), ("104.16.0.2", 30), ("104.16.0.3", 20)) if ip in ips]
        selected, fallback = pool.rank_channels(groups, latency, 2)
        self.assertFalse(fallback)
        self.assertEqual(selected, {
            ("104.16.0.1", 443, "JP", "ip.zip"),
            ("104.16.0.3", 2053, "JP", "ip.zip"),
            ("104.17.0.1", 443, "HK", "generic-cm"),
        })

    def test_country_scopes_get_only_classified_top_and_previous_is_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            items = []
            for scope, mappings in (
                ("focus-JP", [("104.16.0.1", "JP", "ip.zip"), ("104.16.0.2", "JP", "ip.zip")]),
                ("focus-HK", [("104.16.0.3", "HK", "cf-bestip")]),
                ("previous", [("104.16.0.4", "JP", "previous")]),
                ("ct-entry", [("104.16.0.5", "CT-SEED", "ct-pool")]),
            ):
                selected_path = base / f"{scope}.txt"
                map_path = base / f"{scope}.csv"
                selected_path.write_text("".join(f"{ip}\n" for ip, _, _ in mappings), encoding="ascii")
                map_path.write_text("".join(f"{ip},{country},{source}\n" for ip, country, source in mappings), encoding="ascii")
                items.append((443, scope, selected_path, map_path, mappings))
            selected = {
                ("104.16.0.1", 443, "JP", "ip.zip"),
                ("104.17.0.1", 443, "HK", "generic-cm"),
                ("104.16.0.5", 443, "HK", "ct-pool"),
            }
            pool.rewrite_work_items(items, selected, set())
            self.assertEqual((base / "focus-JP.txt").read_text(), "104.16.0.1\n")
            self.assertIn("104.17.0.1,HK,generic-cm", (base / "focus-HK.csv").read_text())
            self.assertNotIn("104.17.0.1", (base / "focus-JP.csv").read_text())
            self.assertEqual((base / "previous.txt").read_text(), "104.16.0.4\n")
            self.assertEqual((base / "ct-entry.txt").read_text(), "")
            self.assertIn("104.16.0.5,HK,ct-pool", (base / "focus-HK.csv").read_text())

    def test_latency_only_cfst_uses_httping_only_for_unlabelled_input(self):
        with tempfile.TemporaryDirectory() as directory:
            commands = []
            def fake_run(command, **kwargs):
                commands.append(command)
                self.assertEqual(kwargs["encoding"], "utf-8")
                self.assertEqual(kwargs["errors"], "replace")
                output = pathlib.Path(command[command.index("-o") + 1])
                output.write_text("IP,Sent,Received,Loss,Latency,Speed,Colo\n104.17.0.1,1,1,0,10,0,HKG\n")
                return type("Result", (), {"returncode": 0, "stderr": ""})()
            with patch.object(pool.subprocess, "run", side_effect=fake_run):
                self.assertEqual(len(pool.cfst_latency("cfst", pathlib.Path(directory), "generic-cm", 443, ["104.17.0.1"], True, "https://cf.xiu2.xyz/url", 420, 2, 30)), 1)
                pool.cfst_latency("cfst", pathlib.Path(directory), "ip.zip", 443, ["104.17.0.1"], False, "https://cf.xiu2.xyz/url", 420, 2, 30)
            self.assertIn("-dd", commands[0])
            self.assertIn("-httping", commands[0])
            self.assertNotIn("-httping", commands[1])
            self.assertNotIn("-dn", commands[0])


if __name__ == "__main__":
    unittest.main()
