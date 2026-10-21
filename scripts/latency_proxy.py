#!/usr/bin/env python3
"""带人为延迟的本地中枢代理 —— 用来模拟「后端在远程服务器上」的网络往返。

用法：
    python3 scripts/latency_proxy.py --port 8099 --upstream http://localhost:8088 --delay 1.5

然后让 App 指向 http://localhost:8099 即可。
"""
import argparse
import http.server
import socketserver
import sys
import threading
import urllib.error
import urllib.request

DELAY = 0.0
UPSTREAM = "http://localhost:8088"
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade", "content-encoding",
    "content-length",
}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _proxy(self, method):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None

        if DELAY:
            threading.Event().wait(DELAY)

        url = UPSTREAM + self.path
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_BY_HOP}
        req = urllib.request.Request(url, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = resp.read()
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() not in HOP_BY_HOP:
                        self.send_header(k, v)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as exc:
            data = exc.read()
            self.send_response(exc.code)
            for k, v in exc.headers.items():
                if k.lower() not in HOP_BY_HOP:
                    self.send_header(k, v)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as exc:
            msg = str(exc).encode()
            self.send_response(502)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)

    def do_GET(self):
        self._proxy("GET")

    def do_POST(self):
        self._proxy("POST")

    def do_PUT(self):
        self._proxy("PUT")

    def do_DELETE(self):
        self._proxy("DELETE")

    def do_PATCH(self):
        self._proxy("PATCH")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    global DELAY, UPSTREAM
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8099)
    ap.add_argument("--upstream", default="http://localhost:8088")
    ap.add_argument("--delay", type=float, default=1.5, help="每个请求的人为延迟（秒）")
    args = ap.parse_args()
    DELAY = args.delay
    UPSTREAM = args.upstream.rstrip("/")
    print(f"⏱  代理 {UPSTREAM} → :{args.port}，每个请求延迟 {args.delay}s", flush=True)
    with Server(("127.0.0.1", args.port), Handler) as httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    main()
