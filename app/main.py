"""Tiny demo web service used to show progressive delivery.

Endpoints:
  /         app response. Counted in metrics. Fails randomly when ERROR_RATE > 0.
  /healthz  always 200 (Kubernetes readiness probe).
  /metrics  Prometheus text format.

Standard library only, so the Docker image needs no dependencies.
"""
import json
import os
import random
import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def make_server(port, version, error_rate):
    lock = threading.Lock()
    counts = {200: 0, 500: 0}  # both series exist from the first scrape

    class Handler(BaseHTTPRequestHandler):
        def _send(self, status, body, ctype="application/json"):
            data = body.encode()
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == "/healthz":
                return self._send(200, "ok", "text/plain")

            if self.path == "/metrics":
                with lock:
                    lines = [
                        "# HELP http_requests_total Requests to / by HTTP status.",
                        "# TYPE http_requests_total counter",
                    ]
                    for status, n in sorted(counts.items()):
                        lines.append(f'http_requests_total{{status="{status}"}} {n}')
                    lines.append("# TYPE app_info gauge")
                    lines.append(f'app_info{{version="{version}"}} 1')
                return self._send(200, "\n".join(lines) + "\n", "text/plain; version=0.0.4")

            if self.path == "/":
                failed = random.random() < error_rate
                status = 500 if failed else 200
                with lock:
                    counts[status] += 1
                body = json.dumps({"version": version, "pod": socket.gethostname(), "ok": not failed})
                return self._send(status, body)

            self._send(404, json.dumps({"error": "not found"}))

        def log_message(self, *args):  # keep container logs quiet
            pass

    return ThreadingHTTPServer(("0.0.0.0", port), Handler)


if __name__ == "__main__":
    server = make_server(
        int(os.environ.get("PORT", "8080")),
        os.environ.get("APP_VERSION", "dev"),
        float(os.environ.get("ERROR_RATE", "0")),
    )
    print("listening", flush=True)
    server.serve_forever()
