import importlib.util
import pathlib
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "domain_candidate_pool.py"
sys.path.insert(0, str(SCRIPT.parent))
spec = importlib.util.spec_from_file_location("domain_candidate_pool", SCRIPT)
pool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pool)


class DomainCandidatePoolTests(unittest.TestCase):
    def test_parse_domain_accepts_hostname_and_optional_port(self):
        self.assertEqual(pool.parse_domain("openai.com"), ("openai.com", None))
        self.assertEqual(pool.parse_domain("www.example.com:8443 # note"), ("www.example.com", 8443))
        self.assertEqual(pool.parse_domain("not a domain"), (None, None))

    def test_rank_is_top_per_country_across_ports(self):
        rows = [
            {"endpoint": "a.example", "port": 443, "country": "SG", "latency": 30, "loss": 0},
            {"endpoint": "b.example", "port": 2053, "country": "SG", "latency": 10, "loss": 0},
            {"endpoint": "c.example", "port": 8443, "country": "SG", "latency": 20, "loss": 0},
            {"endpoint": "d.example", "port": 443, "country": "JP", "latency": 40, "loss": 0},
        ]
        selected = pool.rank_domains(rows, 2, 420)
        self.assertEqual([(x["country"], x["endpoint"]) for x in selected], [("JP", "d.example"), ("SG", "b.example"), ("SG", "c.example")])

    def test_work_items_keep_domains_and_group_by_country_port(self):
        rows = [
            {"endpoint": "a.example.com", "port": 443, "country": "SG", "colo": "SIN", "sent": 3, "received": 3, "loss": 0, "latency": 20},
            {"endpoint": "b.example.com", "port": 2053, "country": "JP", "colo": "NRT", "sent": 3, "received": 2, "loss": 1 / 3, "latency": 40},
        ]
        with tempfile.TemporaryDirectory() as directory:
            manifest = pool.write_work_items(directory, rows)
            self.assertEqual(len(manifest), 2)
            text = pathlib.Path(directory, "domain-bestcf-SG-443.txt").read_text()
            self.assertEqual(text, "a.example.com\n")
            csv_text = pathlib.Path(directory, "CloudflareSpeedTest-2053-domain-JP.csv").read_text()
            self.assertIn("b.example.com,3,2,0.33,40,0,NRT", csv_text)


if __name__ == "__main__":
    unittest.main()
