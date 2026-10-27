import argparse
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
import bestcf_probe as probe
import probe_endpoints as endpoints


class EndpointTests(unittest.TestCase):
    def setUp(self):
        self.profile = dict(endpoints.DEFAULT_PROFILES[1])

    def test_reject_malformed_profiles(self):
        for overrides in ({"host": "https://example.com"}, {"identity_path": "//elsewhere"},
                          {"download_path": "/bad\r\nheader"}, {"identity_format": "html"}):
            with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                endpoints.validate_profile(dict(self.profile, **overrides))

    def test_fallback_requires_identity_and_actual_download(self):
        first, second = endpoints.DEFAULT_PROFILES
        with mock.patch.object(endpoints, "request_identity", side_effect=[
            (None, 0, 0, "identity_tls_error", "TLS failed"),
            ({"colo": "LAX"}, 20, 200, "ok", ""),
        ]), mock.patch.object(endpoints, "request_download", return_value=(1, 262144, .25, 200, "ok", "")) as download:
            selected, checks = endpoints.select_endpoint([first, second], ["104.16.0.1"])
        self.assertEqual(selected["name"], "cloudflare-speed")
        self.assertEqual(len(checks), 2)
        self.assertEqual(download.call_args.args[-1]["host"], second["host"])

    def test_identity_alone_is_not_healthy(self):
        with mock.patch.object(endpoints, "request_identity", return_value=({"colo": "LAX"}, 10, 200, "ok", "")), \
                mock.patch.object(endpoints, "request_download", return_value=(0, 0, 1, 403, "http_error", "403")):
            selected, _ = endpoints.select_endpoint([self.profile], ["104.16.0.1"])
        self.assertIsNone(selected)

    def test_failed_health_check_removes_stale_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "selected.json"
            diagnostics = pathlib.Path(directory) / "health.json"
            output.write_text(json.dumps(self.profile))
            with mock.patch.object(sys, "argv", ["probe_endpoints", "--output", str(output), "--diagnostics", str(diagnostics)]), \
                    mock.patch.object(endpoints, "select_endpoint", return_value=(None, [])), self.assertRaises(SystemExit):
                endpoints.main()
            self.assertFalse(output.exists())
            self.assertIsNone(json.loads(diagnostics.read_text())["selected"])

    def test_trace_uses_destination_colo_not_client_country(self):
        response = mock.Mock(status=200)
        response.read.return_value = b"h=speed.cloudflare.com\nip=203.0.113.1\ncolo=NRT\nloc=CN\n"
        connection = mock.Mock()
        connection.getresponse.return_value = response
        with mock.patch.object(probe, "DirectHTTPSConnection", return_value=connection):
            data, _, _, status, _ = probe.request_identity("104.16.0.1", 443, "", 4, self.profile)
        self.assertEqual(status, "ok")
        self.assertEqual(data["country"], "JP")
        self.assertTrue(connection.request.call_args.args[1].startswith("/cdn-cgi/trace?"))

    def test_trace_rejects_wrong_host_unknown_colo_or_missing_ip(self):
        for body in (b"h=elsewhere\nip=203.0.113.1\ncolo=NRT", b"h=speed.cloudflare.com\ncolo=NRT",
                     b"h=speed.cloudflare.com\nip=203.0.113.1\ncolo=???"):
            response = mock.Mock(status=200)
            response.read.return_value = body
            connection = mock.Mock()
            connection.getresponse.return_value = response
            with self.subTest(body=body), mock.patch.object(probe, "DirectHTTPSConnection", return_value=connection):
                data, _, _, status, _ = probe.request_identity("104.16.0.1", 443, "", 4, self.profile)
            self.assertIsNone(data)
            self.assertEqual(status, "identity_invalid_trace")

    def test_download_rejects_error_pages_with_http_200(self):
        response = mock.Mock(status=200)
        response.getheader.return_value = "text/html; charset=utf-8"
        connection = mock.Mock()
        connection.getresponse.return_value = response
        with mock.patch.object(probe, "DirectHTTPSConnection", return_value=connection):
            _, count, _, _, status, _ = probe.request_download("104.16.0.1", 443, "", 100, 1, 4, self.profile)
        self.assertEqual(status, "invalid_body")
        self.assertEqual(count, 0)
        connection.close.assert_called_once()

    def test_static_file_download_is_byte_capped(self):
        response = mock.Mock(status=200)
        response.getheader.return_value = "application/octet-stream"
        response.read1.side_effect = lambda n: b"x" * n
        connection = mock.Mock()
        connection.getresponse.return_value = response
        profile = dict(self.profile, download_path="/100MB.zip")
        with mock.patch.object(probe, "DirectHTTPSConnection", return_value=connection):
            _, count, _, _, status, _ = probe.request_download("104.16.0.1", 443, "", 100, 1, 4, profile)
        self.assertEqual(status, "ok")
        self.assertEqual(count, 100)
        response.read1.assert_called_once_with(100)

    def test_probe_passes_same_profile_to_identity_and_download(self):
        args = argparse.Namespace(port=443, host_suffix="", timeout=4, download_bytes=100,
                                  duration=1, min_speed_mbps=.03, endpoint_profile=self.profile)
        with mock.patch.object(probe, "request_identity", return_value=({"colo": "NRT"}, 10, 200, "ok", "")) as identity, \
                mock.patch.object(probe, "request_download", return_value=(20, 100, .01, 200, "ok", "")) as download:
            result = probe.probe(["104.16.0.1"], "JP", args, {})
        self.assertEqual(result["status"], "ok")
        self.assertIs(identity.call_args.args[-1], self.profile)
        self.assertIs(download.call_args.args[-1], self.profile)


if __name__ == "__main__":
    unittest.main()
