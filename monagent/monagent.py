#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
monagent - минимальный агент мониторинга.

Слушает TCP-порт, отдаёт метрики в виде JSON на /metrics
и на /healthz отдаёт состояние. Работает без внешних зависимостей.
"""
import json
import os
import socket
import socketserver
import ssl
import sys
import threading
import time
import resource
from datetime import datetime, timezone

VERSION = "1.0.0"
STARTED = time.time()
LOCK = threading.Lock()
COUNTERS = {"requests": 0, "errors": 0}


def uptime():
    return round(time.time() - STARTED, 1)


def cpu_percent():
    # мгновенная загрузка одного интервала через /proc/stat
    try:
        with open("/proc/stat") as f:
            parts = f.readline().split()
        vals = [int(x) for x in parts[1:]]
        idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
        total = sum(vals)
        time.sleep(0.1)
        with open("/proc/stat") as f:
            parts2 = f.readline().split()
        vals2 = [int(x) for x in parts2[1:]]
        idle2 = vals2[3] + (vals2[4] if len(vals2) > 4 else 0)
        total2 = sum(vals2)
        dt = total2 - total
        di = idle2 - idle
        if dt == 0:
            return 0.0
        return round(100.0 * (1.0 - di / dt), 2)
    except Exception:
        return -1.0


def mem_info():
    info = {}
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                k, _, v = line.partition(":")
                info[k] = int(v.split()[0])  # kB
    except Exception:
        pass
    total = info.get("MemTotal", 0)
    avail = info.get("MemAvailable", 0)
    return {
        "total_mb": round(total / 1024, 1),
        "available_mb": round(avail / 1024, 1),
        "used_percent": round(100.0 * (1 - avail / total), 2) if total else -1,
    }


def disk_info(path="/"):
    st = os.statvfs(path)
    total = st.f_blocks * st.f_frsize
    free = st.f_bavail * st.f_frsize
    return {
        "path": path,
        "total_gb": round(total / 1024 ** 3, 1),
        "free_gb": round(free / 1024 ** 3, 1),
        "used_percent": round(100.0 * (1 - free / total), 2) if total else -1,
    }


def self_info():
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return {
        "pid": os.getpid(),
        "rss_mb": round(rss / 1024, 1),
        "threads": threading.active_count(),
        "fd_count": len(os.listdir("/proc/self/fd")),
        "version": VERSION,
    }


def collect():
    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "uptime_sec": uptime(),
        "cpu_percent": cpu_percent(),
        "memory": mem_info(),
        "disk": disk_info("/"),
        "self": self_info(),
        "counters": dict(COUNTERS),
    }


def health():
    d = collect()
    problems = []
    if d["disk"]["used_percent"] > 90:
        problems.append("диск заполнен более чем на 90%")
    if d["memory"]["used_percent"] > 90:
        problems.append("память занята более чем на 90%")
    if d["self"]["fd_count"] > 500:
        problems.append("слишком много открытых дескрипторов")
    return {
        "status": "ok" if not problems else "degraded",
        "problems": problems,
        "uptime_sec": d["uptime_sec"],
    }


class Handler(socketserver.StreamRequestHandler):
    timeout = 10

    def handle(self):
        with LOCK:
            COUNTERS["requests"] += 1
        try:
            line = self.rfile.readline(8192).decode("latin-1", "replace").strip()
            if not line:
                return
            parts = line.split()
            path = parts[1] if len(parts) > 1 else "/"
            # принимаем и игнорируем заголовки до пустой строки
            while True:
                h = self.rfile.readline(8192)
                if not h or h in (b"\r\n", b"\n"):
                    break
        except Exception:
            with LOCK:
                COUNTERS["errors"] += 1
            return

        if path.startswith("/metrics"):
            body, code, ctype = json.dumps(collect(), ensure_ascii=False, indent=2), 200, "application/json; charset=utf-8"
        elif path.startswith("/healthz"):
            h = health()
            body = json.dumps(h, ensure_ascii=False, indent=2)
            code = 200 if h["status"] == "ok" else 503
            ctype = "application/json; charset=utf-8"
        elif path in ("/", ""):
            body = (
                "monagent %s\n\n"
                "/metrics  - подробные метрики (JSON)\n"
                "/healthz  - состояние: 200 ok / 503 degraded\n"
            ) % VERSION
            code, ctype = 200, "text/plain; charset=utf-8"
        else:
            body, code, ctype = "not found\n", 404, "text/plain; charset=utf-8"

        if code >= 500:
            with LOCK:
                COUNTERS["errors"] += 1
        resp = (
            "HTTP/1.1 %d %s\r\n"
            "Content-Type: %s\r\n"
            "Content-Length: %d\r\n"
            "Server: monagent/%s\r\n"
            "Connection: close\r\n\r\n%s"
        ) % (code, "OK" if code == 200 else ("SERVICE UNAVAILABLE" if code == 503 else "NOT FOUND"),
             ctype, len(body.encode("utf-8")), VERSION, body)
        try:
            self.wfile.write(resp.encode("utf-8"))
        except Exception:
            with LOCK:
                COUNTERS["errors"] += 1


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    if len(sys.argv) < 4:
        print("использование: monagent.py <host> <port> <certfile> <keyfile>", file=sys.stderr)
        return 2
    host, port = sys.argv[1], int(sys.argv[2])
    certfile, keyfile = sys.argv[3], sys.argv[4]

    srv = Server((host, port), Handler)

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(certfile, keyfile)
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)

    sys.stderr.write("monagent %s слушает https://%s:%d\n" % (VERSION, host, port))
    sys.stderr.flush()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
