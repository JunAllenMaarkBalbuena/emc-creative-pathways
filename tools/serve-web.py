#!/usr/bin/env python3
"""Serve a Godot web export locally so it can be verified in a real browser.

Why this exists rather than "just open index.html":

  1. A Godot web export must be served over HTTP. The service worker will not
     register from file://, and the engine fetches its payload with XHR/fetch,
     which file:// blocks.
  2. The server MUST handle concurrent requests. The engine fetches index.js,
     index.wasm and index.pck in parallel. A single-threaded server serialises
     them, the browser gives up waiting, and index.wasm fails with
     net::ERR_ABORTED. That failure looks exactly like a broken export and is
     not one - it is the harness. Check this before blaming the build.
  3. The server MUST support HTTP Range. index.pck is around 255 MB and is
     fetched with range requests.

Both failure modes above were hit while producing the evidence recorded in
docs/decisions/2026-10-04-ci-export.md. Python's ThreadingHTTPServer plus a
Range-aware handler is the smallest thing that satisfies all three.

Usage:
    python tools/serve-web.py --root build/web
    python tools/serve-web.py --root build/web --port 8123

Then open the printed URL. To check the game is actually rendering rather than
just that the engine started, read the canvas drawing buffer from inside a
requestAnimationFrame callback - see the note in that decision doc.

This is a local test harness. It is not a production server and binds to
loopback only.
"""

import argparse
import os
import re
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

RANGE_RE = re.compile(r"bytes=(\d*)-(\d*)")

MIME = {
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".js": "application/javascript",
    ".json": "application/json",
    ".ogv": "video/ogg",
    ".ogg": "audio/ogg",
    ".html": "text/html",
    ".png": "image/png",
    # Godot ships these alongside the generated PWA icons. They are editor
    # sidecars, not runtime assets, and nothing should ever request them.
    ".import": "text/plain",
}


class _Limited:
    """File-like wrapper that stops after `remaining` bytes, for a 206 body."""

    def __init__(self, fp, remaining):
        self.fp = fp
        self.remaining = remaining

    def read(self, n=-1):
        if self.remaining <= 0:
            return b""
        if n is None or n < 0:
            n = self.remaining
        n = min(n, self.remaining)
        data = self.fp.read(n)
        self.remaining -= len(data)
        return data

    def close(self):
        self.fp.close()


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, **MIME}

    def end_headers(self):
        # Iterating on a build with a warm cache is a reliable way to test a
        # stale payload and conclude the fix did not work.
        self.send_header("Cache-Control", "no-store")
        self.send_header("Accept-Ranges", "bytes")
        super().end_headers()

    def send_head(self):
        rng = self.headers.get("Range")
        if not rng:
            return super().send_head()

        path = self.translate_path(self.path)
        if os.path.isdir(path) or not os.path.isfile(path):
            return super().send_head()

        m = RANGE_RE.match(rng.strip())
        if not m:
            return super().send_head()

        size = os.path.getsize(path)
        start = int(m.group(1)) if m.group(1) else 0
        end = int(m.group(2)) if m.group(2) else size - 1
        if end >= size:
            end = size - 1
        length = end - start + 1

        if start >= size or length <= 0:
            self.send_error(416, "Requested Range Not Satisfiable")
            return None

        f = open(path, "rb")
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(length))
        self.end_headers()
        f.seek(start)
        return _Limited(f, length)

    def log_message(self, fmt, *args):
        sys.stderr.write("  %s\n" % (fmt % args))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", required=True, help="directory holding index.html")
    ap.add_argument("--port", type=int, default=8123)
    a = ap.parse_args()

    if not os.path.isfile(os.path.join(a.root, "index.html")):
        sys.exit(f"no index.html in {a.root} - build the Web preset first")

    root = os.path.abspath(a.root)
    handler = lambda *args, **kw: Handler(*args, directory=root, **kw)
    httpd = ThreadingHTTPServer(("127.0.0.1", a.port), handler)
    print(
        f"serving {root} on http://127.0.0.1:{a.port}/ "
        f"(threaded, range ok)",
        flush=True,
    )
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped", flush=True)


if __name__ == "__main__":
    main()
