#!/usr/bin/env python3
"""brain-capture-check — Claude Code Stop hook.

Closes the capture loop. The SessionStart and UserPromptSubmit hooks make the
vault arrive automatically; nothing made it *fill*. Capture depended on Claude
remembering to write a note, which is exactly the kind of thing that gets
dropped at the end of a long session.

So: when a substantive session is about to end and nothing was written to the
vault, block the stop once and say so. The model then writes the note (or
explains why there's nothing worth writing) and stops for real.

Deliberately quiet. It stays out of the way when:
  - the session is short or mechanical (nothing was worked out)
  - something was already written to the vault
  - it's a peek session (a floating one-question window, not a work session)
  - it already fired once for this session
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

VAULT = Path(os.environ.get("BRAIN_VAULT", Path.home() / "Documents" / "Brain"))
MARK_DIR = Path.home() / ".cache" / "brain-capture"

# Files the automation writes by itself — writing these is not "capture".
AUTO = ("Claude/Sessions/", "Claude/Health.md", "Claude/Inbox.md",
        "Claude/.health-score", "Claude/Rollups/")

MIN_USER_TURNS = 3
MIN_ASSISTANT_CHARS = 2500

REASON = (
    "Stop hook (brain-capture-check): this session looks substantive but nothing "
    "was written to the Obsidian vault at ~/Documents/Brain.\n\n"
    "Before stopping, do the capture step from CLAUDE.md:\n"
    "  1. If the user worked something out, decided something, or hit a non-obvious "
    "gotcha — write it into the right existing folder in their own phrasing, or "
    "append a few lines to the note that already covers it. Link only to notes that "
    "exist. Tell them in one line that you saved it.\n"
    "  2. Update the 'Active threads' section of Claude/INDEX.md if work started, "
    "finished, or changed status.\n"
    "  3. Append the *why* (decisions, rationale) to today's Claude/Sessions note.\n\n"
    "If there is genuinely nothing worth keeping — the session was debugging noise, "
    "or the user never reached a conclusion — say that in one sentence and stop. "
    "An honest gap beats a note they won't trust. Do not invent a note to satisfy "
    "this hook."
)


def transcript_stats(path: Path):
    """(user turns, assistant chars, wrote_to_vault)."""
    turns, chars, wrote = 0, 0, False
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError:
        return 0, 0, True  # can't tell → stay silent

    for line in lines:
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        msg = ev.get("message") or {}
        role = msg.get("role") or ev.get("type")
        content = msg.get("content")

        if role == "user":
            # Hook injections and tool results arrive as "user" events; only a
            # plain string (or a text block) is a human turn.
            if isinstance(content, str):
                if "<system-reminder>" not in content:
                    turns += 1
            elif isinstance(content, list):
                if any(b.get("type") == "text" for b in content if isinstance(b, dict)):
                    turns += 1
        elif role == "assistant" and isinstance(content, list):
            for b in content:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "text":
                    chars += len(b.get("text") or "")
                elif b.get("type") == "tool_use" and b.get("name") in ("Write", "Edit", "NotebookEdit"):
                    fp = str((b.get("input") or {}).get("file_path") or "")
                    if fp.startswith(str(VAULT)):
                        rel = fp[len(str(VAULT)):].lstrip("/")
                        if not rel.startswith(AUTO):
                            wrote = True
    return turns, chars, wrote


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    # Never loop: if we already blocked and the model is stopping again, let it.
    if payload.get("stop_hook_active"):
        return 0
    # peek is a one-question floating window, not a work session.
    if os.environ.get("PEEK") == "1":
        return 0
    if not VAULT.is_dir():
        return 0

    tpath = payload.get("transcript_path")
    if not tpath:
        return 0

    sid = str(payload.get("session_id") or "unknown")
    mark = MARK_DIR / sid
    if mark.exists():
        return 0

    turns, chars, wrote = transcript_stats(Path(tpath).expanduser())
    if wrote or turns < MIN_USER_TURNS or chars < MIN_ASSISTANT_CHARS:
        return 0

    MARK_DIR.mkdir(parents=True, exist_ok=True)
    mark.touch()
    print(json.dumps({"decision": "block", "reason": REASON}))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # A capture check must never wedge the session.
        sys.exit(0)
