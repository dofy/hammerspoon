#!/usr/bin/env python3
"""Live keystats dashboard.

Serves report.html together with a JSON API over the SQLite database the
Hammerspoon collector writes. The page polls the API, so numbers follow the
collector's flush interval instead of a one-off static snapshot.

The database is opened read-only; the collector keeps writing to it in WAL mode
and concurrent readers are fine. Binds to 127.0.0.1 only: this data is a record
of every shortcut pressed, and it has no business on the network.
"""

import argparse
import json
import os
import re
import sqlite3
import time
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

LOCAL = ("unixepoch", "localtime")
KEY_LABEL = "CASE WHEN length(k.name)=1 THEN upper(k.name) ELSE k.name END"

FROM = """
  FROM event e
  JOIN app a ON a.id = e.app_id
  LEFT JOIN keyname k ON k.keycode = e.keycode
"""


def epoch_of(value: str) -> int:
    """Accepts: all | today | yesterday | now | 7d | 24h | 90m | 4w | 3mo | YYYY-MM-DD."""
    v = (value or "").strip()
    now = datetime.now()
    if v in ("", "all"):
        return 0
    if v == "now":
        return int(now.timestamp())
    if v == "today":
        return int(now.replace(hour=0, minute=0, second=0, microsecond=0).timestamp())
    if v == "yesterday":
        base = now.replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=1)
        return int(base.timestamp())
    m = re.fullmatch(r"(\d+)(mo|[dwhm])", v)
    if m:
        n, unit = int(m.group(1)), m.group(2)
        delta = {
            "d": timedelta(days=n),
            "w": timedelta(weeks=n),
            "h": timedelta(hours=n),
            "m": timedelta(minutes=n),
            "mo": timedelta(days=30 * n),
        }[unit]
        return int((now - delta).timestamp())
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", v):
        return int(datetime.strptime(v, "%Y-%m-%d").timestamp())
    raise ValueError(f"cannot parse time {value!r}")


def rows(con, sql, params=()):
    cur = con.execute(sql, params)
    cols = [c[0] for c in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def payload(con, since: str) -> dict:
    ts_from, ts_to = epoch_of(since), int(time.time())
    where = "e.ts >= ? AND e.ts <= ?"
    p = (ts_from, ts_to)

    meta = rows(con, f"""
        SELECT coalesce(sum(e.n), 0) AS total,
               count(DISTINCT e.mods || '/' || e.keycode) AS combos,
               count(DISTINCT a.id) AS apps,
               strftime('%Y-%m-%d %H:%M', min(e.ts), ?, ?) AS first_event,
               strftime('%Y-%m-%d %H:%M', max(e.ts), ?, ?) AS last_event
        {FROM} WHERE {where}""", (*LOCAL, *LOCAL, *p))[0]
    meta.update(since=since, ts_from=ts_from, ts_to=ts_to,
                live=True, generated=int(time.time()))

    data = {
        "meta": meta,
        "combos": rows(con, f"""
            SELECT a.name AS app, e.mods AS mods, k.name AS key, sum(e.n) AS n
            {FROM} WHERE {where} GROUP BY 1, 2, 3 ORDER BY n DESC""", p),
        "timeline": rows(con, f"""
            SELECT (e.ts / 3600) * 3600 AS h, a.name AS app, sum(e.n) AS n
            {FROM} WHERE {where} GROUP BY 1, 2 ORDER BY 1""", p),
        "switches": rows(con, f"""
            SELECT e.mods AS mods, k.name AS key, s.name AS target, sum(e.n) AS n
            {FROM} JOIN app s ON s.id = e.switch_to
            WHERE {where} GROUP BY 1, 2, 3 ORDER BY n DESC""", p),
    }
    return data


class Handler(BaseHTTPRequestHandler):
    server_version = "keystats"

    def log_message(self, fmt, *args):  # quiet by default
        if self.server.verbose:
            super().log_message(fmt, *args)

    def _send(self, code, body: bytes, ctype: str):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path in ("/", "/index.html"):
            with open(self.server.template, encoding="utf-8") as fh:
                page = fh.read()
            page = page.replace("/*__KEYSTATS_API__*/null", '"/api/stats"')
            return self._send(200, page.encode("utf-8"), "text/html; charset=utf-8")

        if url.path == "/api/stats":
            q = parse_qs(url.query)
            since = (q.get("since") or ["7d"])[0]
            try:
                con = sqlite3.connect(f"file:{self.server.db}?mode=ro", uri=True)
                try:
                    body = json.dumps(payload(con, since)).encode("utf-8")
                finally:
                    con.close()
            except ValueError as exc:
                return self._send(400, json.dumps({"error": str(exc)}).encode(),
                                  "application/json; charset=utf-8")
            except sqlite3.Error as exc:
                return self._send(500, json.dumps({"error": str(exc)}).encode(),
                                  "application/json; charset=utf-8")
            return self._send(200, body, "application/json; charset=utf-8")

        if url.path == "/favicon.ico":          # keep the console clean
            return self._send(204, b"", "image/x-icon")

        self._send(404, b"not found", "text/plain; charset=utf-8")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="serve the live keystats dashboard")
    ap.add_argument("--db", default=os.path.expanduser("~/.local/share/keystats/keystats.db"))
    ap.add_argument("--template", default=os.path.join(here, "report.html"))
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(args.db):
        raise SystemExit(f"keystats: no database at {args.db}")

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    httpd.db, httpd.template, httpd.verbose = args.db, args.template, args.verbose
    print(f"keystats: serving http://{args.host}:{args.port}  (db: {args.db})", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nkeystats: stopped")


if __name__ == "__main__":
    main()
