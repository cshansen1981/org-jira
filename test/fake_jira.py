#!/usr/bin/env python3
"""Minimal fake Jira Server used by the HTTP tests.

Serves /rest/api/2/myself and /rest/api/2/search (with real startAt /
maxResults paging over five fixture issues) and requires the header
"Authorization: Bearer <TOKEN>".  Binds to an ephemeral port and prints
"PORT <n>" on stdout once it is listening.

Usage: fake_jira.py [TOKEN]   (default token: test-token)
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

TOKEN = sys.argv[1] if len(sys.argv) > 1 else "test-token"

SUMMARIES = [
    "Æble ø å",
    "Pipe | and [brackets]",
    'Quote "inside" summary',
    "A very long summary that certainly exceeds fifty characters in length",
    "Plain",
]


def issue(i, summary):
    return {
        "key": f"TST-{i}",
        "fields": {
            "summary": summary,
            "status": {"name": "To Do"},
            "priority": {"name": "High"},
            "issuetype": {"name": "Task"},
            "project": {"key": "TST"},
            "updated": "2026-01-01T00:00:00.000+0000",
        },
    }


ISSUES = [issue(i + 1, s) for i, s in enumerate(SUMMARIES)]


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json;charset=UTF-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.headers.get("Authorization") != f"Bearer {TOKEN}":
            return self._send(401, {"errorMessages": ["Unauthorized"]})
        url = urlparse(self.path)
        qs = parse_qs(url.query)
        if url.path == "/rest/api/2/myself":
            return self._send(200, {"displayName": "Søren Åberg", "name": "soren"})
        if url.path == "/rest/api/2/search":
            start = int(qs.get("startAt", ["0"])[0])
            size = int(qs.get("maxResults", ["50"])[0])
            return self._send(200, {
                "startAt": start,
                "maxResults": size,
                "total": len(ISSUES),
                "jql": qs.get("jql", [""])[0],
                "issues": ISSUES[start:start + size],
            })
        self._send(404, {"errorMessages": ["Not found"]})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 0), Handler)
    print(f"PORT {server.server_port}", flush=True)
    server.serve_forever()
