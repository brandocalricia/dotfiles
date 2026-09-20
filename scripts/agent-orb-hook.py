#!/usr/bin/python3
"""Fail-open status feed for the agent-orb overlay. Always exits 0. No stdout."""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

TOOL_STATE = {
    "web_search": "searching",
    "web_fetch": "searching",
    "open_page": "searching",
    "open_page_with_find": "searching",
    "grep": "searching",
    "search_tool": "searching",
    "x_keyword_search": "searching",
    "x_semantic_search": "searching",
    "x_user_search": "searching",
    "x_thread_fetch": "searching",
    "read_file": "searching",
    "list_dir": "searching",
    "glob": "searching",
    "run_terminal_command": "working",
    "bash": "working",
    "search_replace": "shaping",
    "write": "shaping",
    "edit": "shaping",
    "todo_write": "shaping",
    "spawn_subagent": "weaving",
    "task": "weaving",
    "use_tool": "connecting",
    "websearch": "searching",
    "webfetch": "searching",
    "read": "searching",
}


def tool_name(d: dict) -> str:
    t = d.get("tool_name") or d.get("toolName") or d.get("tool") or ""
    if isinstance(t, dict):
        t = t.get("name") or t.get("tool") or ""
    return str(t or "")


def state_for(name: str) -> str:
    low = name.strip().lower()
    if low in TOOL_STATE:
        return TOOL_STATE[low]
    tail = low.rsplit("__", 1)[-1]
    if tail in TOOL_STATE:
        return TOOL_STATE[tail]
    return "working"


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
    busy = True
    state = "working"
    what = ""
    if event in ("Stop", "StopCancelled", "StopFailure", "SessionEnd"):
        busy = False
        state = "listening"
    elif event == "Notification":
        kind = str(
            data.get("notificationType") or data.get("type") or data.get("reason") or ""
        )
        if kind == "permission_prompt":
            state = "listening"
            busy = True
        elif kind in ("idle_prompt", "task_complete"):
            busy = False
            state = "listening"
        else:
            state = "working"
    elif event == "UserPromptSubmit":
        state = "breathing"
    elif event == "SubagentStart":
        state = "weaving"
    elif event in ("PreToolUse", "PostToolUse", "PostToolUseFailure"):
        state = state_for(tool)
        what = tool.replace("_", " ")
    elif event == "SessionStart":
        state = "connecting"
        busy = False
    elif tool:
        state = state_for(tool)
        what = tool.replace("_", " ")
    rec = {
        "busy": busy,
        "state": state,
        "verb": tool or event,
        "what": what,
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
