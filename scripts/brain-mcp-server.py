#!/usr/bin/env python3
"""brain MCP server — one tool, brain_search(query), ranking from brain-retrieve.py.

Speaks MCP stdio. Accepts Content-Length (LSP) framing or NDJSON, and replies
in whichever framing the client used.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "brain_retrieve", HERE / "brain-retrieve.py"
)
_mod = importlib.util.module_from_spec(_spec)
assert _spec.loader is not None
_spec.loader.exec_module(_mod)
retrieve = _mod.retrieve

# Unbuffered
try:
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
except Exception:
    pass

TOOL = {
    "name": "brain_search",
    "description": (
        "Search the user's Obsidian vault at ~/Documents/Brain and return the "
        "notes that actually bear on the query. Call this BEFORE answering any "
        "question about the user's projects, setup, decisions, tools, machines, "
        "games, or history. Returns a 'From your vault' block, or a silent-empty "
        "marker if nothing matched."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "query": {
                "type": "string",
                "description": "The user's prompt or question, verbatim if possible.",
            }
        },
        "required": ["query"],
    },
}

# Last observed framing from the client.
_USE_HEADERS = True


def _log(raw: bytes) -> None:
    try:
        p = Path.home() / ".cache" / "brain-hooks" / "mcp-wire.log"
        p.parent.mkdir(parents=True, exist_ok=True)
        with p.open("ab") as f:
            f.write(raw)
            f.write(b"\n")
    except OSError:
        pass


def _read_message():
    global _USE_HEADERS
    header = sys.stdin.buffer.readline()
    if not header:
        return None
    _log(b"IN " + header)
    if header.lower().startswith(b"content-length:"):
        _USE_HEADERS = True
        n = int(header.split(b":", 1)[1].strip())
        while True:
            line = sys.stdin.buffer.readline()
            _log(b"INH " + line)
            if line in (b"\r\n", b"\n", b""):
                break
        body = sys.stdin.buffer.read(n)
        _log(b"INB " + body)
        return json.loads(body.decode("utf-8"))
    _USE_HEADERS = False
    line = header
    while line.endswith(b"\n") or line.endswith(b"\r"):
        line = line[:-1]
    if not line.strip():
        return _read_message()
    return json.loads(line.decode("utf-8"))


def _write_message(msg: dict) -> None:
    blob = json.dumps(msg, ensure_ascii=False).encode("utf-8")
    if _USE_HEADERS:
        frame = f"Content-Length: {len(blob)}\r\n\r\n".encode("ascii") + blob
    else:
        frame = blob + b"\n"
    _log(b"OUT " + frame)
    sys.stdout.buffer.write(frame)
    sys.stdout.buffer.flush()


def _result(id_, result):
    _write_message({"jsonrpc": "2.0", "id": id_, "result": result})


def _error(id_, code, message):
    _write_message({"jsonrpc": "2.0", "id": id_, "error": {"code": code, "message": message}})


def handle(msg: dict) -> None:
    method = msg.get("method")
    id_ = msg.get("id")
    params = msg.get("params") or {}
    if method is None:
        return
    if isinstance(method, str) and method.startswith("notifications/"):
        return
    if method == "initialize":
        _result(id_, {
            "protocolVersion": params.get("protocolVersion") or "2024-11-05",
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "brain", "version": "1.0"},
        })
        return
    if method == "tools/list":
        _result(id_, {"tools": [TOOL]})
        return
    if method == "ping":
        _result(id_, {})
        return
    if method == "tools/call":
        name = params.get("name")
        args = params.get("arguments") or {}
        if name != "brain_search":
            _error(id_, -32601, f"unknown tool {name}")
            return
        query = args.get("query") or ""
        try:
            ctx = retrieve(query)
        except Exception as e:
            _result(id_, {
                "content": [{"type": "text", "text": f"(brain_search failed: {e})"}],
                "isError": True,
            })
            return
        text = ctx if ctx else (
            "(no matching vault notes — stay silent about the vault and answer normally)"
        )
        _result(id_, {"content": [{"type": "text", "text": text}]})
        return
    if id_ is not None:
        _error(id_, -32601, f"unknown method {method}")


def main() -> int:
    while True:
        try:
            msg = _read_message()
        except Exception as e:
            _log(f"READERR {e}".encode())
            continue
        if msg is None:
            return 0
        try:
            handle(msg)
        except Exception as e:
            _log(f"HANDLEERR {e}".encode())
            if isinstance(msg, dict) and msg.get("id") is not None:
                _error(msg["id"], -32603, str(e))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (BrokenPipeError, KeyboardInterrupt):
        sys.exit(0)
