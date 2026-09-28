#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Версия 1 - рабочая. Отвечает 200 на /healthz."""
import json
import os
import socket
import socketserver
import sys
import threading
import time

VERSION = "1.0.0"
STARTED = time.time()
LOCK = threading.Lock()
HITS = {"n": 0}


def health():
    # у v1 всё хорошо
    return 200, {"status": "ok", "version": VERSION,
                 "uptime": round(time.time() - STARTED, 1)}


class H(socketserver.StreamRequestHandler):
    timeout = 10

    def handle(self):
        try:
            line = self.rfile.readline(8192).decode("latin-1", "replace").strip()
            if not line:
                return
            p = line.split()
            path = p[1] if len(p) > 1 else "/"
            while True:
                h = self.rfile.readline(8192)
                if not h or h in (b"\r\n", b"\n"):
                    break
        except Exception:
            return
        with LOCK:
            HITS["n"] += 1
        if path.startswith("/healthz"):
            code, obj = health()
            body = json.dumps(obj, ensure_ascii=False)
        elif path.startswith("/"):
            code = 200
            body = json.dumps({"version": VERSION, "hits": HITS["n"]})
        else:
            code, body = 404, "not found\n"
        resp = ("HTTP/1.1 %d X\r\nContent-Type: application/json; "
                "Content-Length: %d\r\nConnection: close\r\n\r\n%s"
                ) % (code, len(body.encode()), body)
        try:
            self.wfile.write(resp.encode())
        except Exception:
            pass


class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
    srv = S(("127.0.0.1", port), H)
    sys.stderr.write("app v%s on 127.0.0.1:%d\n" % (VERSION, port))
    sys.stderr.flush()
    srv.serve_forever()
