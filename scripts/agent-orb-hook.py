#!/usr/bin/python3
"""Fail-open status feed for the agent-orb Waybar chip. Always exits 0. No stdout."""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, "/home/brandonrobertniehaus/code/agent-orb")
try:
    from states import state_for_event, state_for_tool
except Exception:
    state_for_event = None  # type: ignore
    state_for_tool = None  # type: ignore


def tool_name(d: dict) -> str:
    t = d.get("tool_name") or d.get("toolName") or d.get("tool") or d.get("name") or ""
    if isinstance(t, dict):
        t = t.get("name") or t.get("tool") or t.get("tool_name") or ""
    return str(t or "")


def agent_pid() -> int:
    pid = os.getppid()
    seen: set[int] = set()
    while pid and pid > 1 and pid not in seen:
        seen.add(pid)
        try:
            comm = Path(f"/proc/{pid}/comm").read_text().strip().lower()
        except OSError:
            break
        if comm in ("grok", "claude"):
            return pid
        try:
            stat = Path(f"/proc/{pid}/stat").read_text()
            rparen = stat.rfind(")")
            pid = int(stat[rparen + 2 :].split()[1])
        except Exception:
            break
    return os.getppid()


def main() -> int:
    state_dir = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "agent-orb"
    try:
        state_dir.mkdir(parents=True, exist_ok=True)
    except OSError:
        return 0
    raw = sys.stdin.read() if not sys.stdin.isatty() else ""
    data: dict = {}
    if raw:
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, dict):
                data = parsed
        except json.JSONDecodeError:
            data = {}
    event = (
        os.environ.get("GROK_HOOK_EVENT")
        or os.environ.get("CLAUDE_HOOK_EVENT")
        or str(data.get("hook_event_name") or data.get("event") or "")
    )
    tool = tool_name(data)
    if event == "Notification":
        kind = str(
            data.get("notificationType") or data.get("type") or data.get("reason") or ""
        )
        if kind == "permission_prompt":
            busy, state = True, "listening"
        elif kind in ("idle_prompt", "task_complete"):
            busy, state = False, "listening"
        else:
            busy, state = True, "working"
    elif state_for_event:
        busy, state = state_for_event(event, tool)
        if event in ("PreToolUse", "PostToolUse", "PostToolUseFailure") and state_for_tool:
            state = state_for_tool(tool) or state
    else:
        busy, state = True, "working"

    rec = {
        "busy": busy,
        "state": state,
        "verb": tool or event,
        "what": (tool.replace("_", " ") if tool else ""),
        "agent": "grok",
        "pid": agent_pid(),
        "ts": time.time(),
        "event": event,
    }
    try:
        (state_dir / "hooks.json").write_text(json.dumps(rec), encoding="utf-8")
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
