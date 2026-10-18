import importlib.util
import json
import pathlib
import threading
import unittest
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("app_main", ROOT / "app" / "main.py")
main = importlib.util.module_from_spec(spec)
spec.loader.exec_module(main)


def get(url):
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as err:
        return err.code, err.read().decode()


class ServerCase(unittest.TestCase):
    error_rate = 0.0

    def setUp(self):
        self.server = main.make_server(0, "vtest", self.error_rate)  # port 0 = any free port
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()


class TestHealthyVersion(ServerCase):
    def test_root_returns_version(self):
        status, body = get(self.base + "/")
        self.assertEqual(status, 200)
        data = json.loads(body)
        self.assertEqual(data["version"], "vtest")
        self.assertTrue(data["ok"])

    def test_healthz(self):
        self.assertEqual(get(self.base + "/healthz")[0], 200)

    def test_unknown_path_404(self):
        self.assertEqual(get(self.base + "/nope")[0], 404)

    def test_metrics_count_requests(self):
        for _ in range(3):
            get(self.base + "/")
        get(self.base + "/healthz")  # must not be counted
        _, text = get(self.base + "/metrics")
        self.assertIn('http_requests_total{status="200"} 3', text)
        self.assertIn('http_requests_total{status="500"} 0', text)
        self.assertIn('app_info{version="vtest"} 1', text)


class TestBadVersion(ServerCase):
    error_rate = 1.0

    def test_root_fails(self):
        self.assertEqual(get(self.base + "/")[0], 500)

    def test_healthz_still_ok(self):
        # A bad release must look healthy to Kubernetes probes. Only the
        # metrics analysis can catch it, which is the point of the demo.
        self.assertEqual(get(self.base + "/healthz")[0], 200)

    def test_errors_show_in_metrics(self):
        get(self.base + "/")
        get(self.base + "/")
        _, text = get(self.base + "/metrics")
        self.assertIn('http_requests_total{status="500"} 2', text)


if __name__ == "__main__":
    unittest.main()
