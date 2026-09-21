import importlib.util
import json
import pathlib
import unittest
from unittest.mock import patch


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "generic_candidate_pool.py"
spec = importlib.util.spec_from_file_location("generic_candidate_pool", SCRIPT)
pool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pool)


class GenericCandidatePoolTests(unittest.TestCase):
    def test_cm_only_accepts_public_ipv4_and_removes_duplicates(self):
        content = "104.17.63.208#CF 移动优选\n104.17.63.208\n::1\n127.0.0.1\ninvalid\n198.41.208.237#CM"
        self.assertEqual(pool.sampled_ips("cm", content, 5, 1), ["104.17.63.208", "198.41.208.237"])

    def test_asn_prefixes_are_bounded_and_rotated(self):
        content = json.dumps({"data": {"prefixes": [
            {"prefix": "104.16.0.0/24"}, {"prefix": "104.17.0.0/24"},
            {"prefix": "104.18.0.0/24"}, {"prefix": "2001:db8::/32"},
            {"prefix": "127.0.0.0/8"},
        ]}})
        self.assertEqual(pool.sampled_ips("as13335", content, 2, 1), ["104.16.0.2", "104.17.0.2"])
        self.assertNotEqual(pool.sampled_ips("as13335", content, 2, 2), pool.sampled_ips("as13335", content, 2, 1))

    def test_tcp_top_is_per_source_and_port_without_country(self):
        with patch.object(pool, "fetch", return_value="104.17.63.208\n198.41.208.237"), patch.object(
            pool, "tcp_latency", side_effect=lambda ip, port, timeout: 1 if ip == "198.41.208.237" else 10
        ):
            rows = pool.select_candidates(["cm"], [443, 2053], 10, 1, 0.1, 2, 1)
        self.assertEqual(rows, [
            ("198.41.208.237", 443, "generic-cm"),
            ("198.41.208.237", 2053, "generic-cm"),
        ])


if __name__ == "__main__":
    unittest.main()
