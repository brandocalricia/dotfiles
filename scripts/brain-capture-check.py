#!/usr/bin/env python3
"""brain-capture-check — Stop hook for Claude Code and Grok Build.

Closes the capture loop. The SessionStart and UserPromptSubmit hooks make the
vault arrive automatically; nothing made it *fill*. Capture depended on the
model remembering to write a note, which is exactly the kind of thing that gets
dropped at the end of a long session.

So: when a substantive session is about to end and nothing was written to the
vault, block the stop once and say so. The model then writes the note (or
explains why there's nothing worth writing) and stops for real.

Deliberately quiet. It stays out of the way when:
  - the session is short or mechanical (nothing was worked out)
  - something was already written to the vault
  - it's a peek session (a floating one-question window, not a work session)
  - it already fired once for this session
  - Grok's observe-only session-end Stop (reason != end_turn)
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

MIN_USER_TURNS = int(os.environ.get("BRAIN_CAPTURE_MIN_TURNS", "3"))
MIN_ASSISTANT_CHARS = int(os.environ.get("BRAIN_CAPTURE_MIN_CHARS", "2500"))

# Claude Write/Edit + Grok write/search_replace (and the Claude names if a
# compat layer ever emits them).
VAULT_WRITE_TOOLS = {
    "Write", "Edit", "MultiEdit", "NotebookEdit",
    "write", "search_replace",
}

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


def _payload_get(payload: dict, *keys, default=None):
    for k in keys:
        v = payload.get(k)
        if v not in (None, ""):
            return v
    return default


def resolve_transcript(path: Path) -> Path:
    """Grok Stop/SessionEnd point at updates.jsonl; chat_history.jsonl is the conversation."""
    if path.name == "updates.jsonl":
        alt = path.with_name("chat_history.jsonl")
        if alt.exists():
            return alt
    return path


def _tool_file_path(name: str, args) -> str:
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except ValueError:
            return ""
    if not isinstance(args, dict):
        return ""
    return str(args.get("file_path") or args.get("path") or "")


def _vault_write(fp: str) -> bool:
    if not fp:
        return False
    fp = str(Path(fp).expanduser())
    vault = str(VAULT)
    if not (fp == vault or fp.startswith(vault + "/")):
        return False
    rel = fp[len(vault):].lstrip("/")
    return not rel.startswith(AUTO)


def transcript_stats(path: Path):
    """(user turns, assistant chars, wrote_to_vault). Claude JSONL and Grok chat_history."""
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

        # --- Claude Code: {type, message: {role, content}} ---
        msg = ev.get("message") or {}
        if msg:
            role = msg.get("role") or ev.get("type")
            content = msg.get("content")
            if role == "user":
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
                    elif b.get("type") == "tool_use" and b.get("name") in VAULT_WRITE_TOOLS:
                        if _vault_write(_tool_file_path(b.get("name") or "", b.get("input") or {})):
                            wrote = True
            continue

        # --- Grok chat_history.jsonl: {type, content, tool_calls?, prompt_index?} ---
        t = ev.get("type")
        if t == "user":
            if ev.get("synthetic_reason"):
                continue
            # Real human prompts carry prompt_index. Fallback: a text block
            # that isn't a harness wrapper.
            if "prompt_index" in ev:
                turns += 1
                continue
            content = ev.get("content")
            texts = []
            if isinstance(content, str):
                texts.append(content)
            elif isinstance(content, list):
                for b in content:
                    if isinstance(b, dict):
                        texts.append(b.get("text") or "")
                    elif isinstance(b, str):
                        texts.append(b)
            blob = "\n".join(texts)
            if blob and not blob.lstrip().startswith("<") and "Caveat" not in blob[:40]:
                turns += 1
        elif t == "assistant":
            content = ev.get("content")
            if isinstance(content, str):
                chars += len(content)
            elif isinstance(content, list):
                for b in content:
                    if isinstance(b, dict) and b.get("type") == "text":
                        chars += len(b.get("text") or "")
                    elif isinstance(b, str):
                        chars += len(b)
            for tc in ev.get("tool_calls") or []:
                if not isinstance(tc, dict):
                    continue
                if tc.get("name") in VAULT_WRITE_TOOLS:
                    if _vault_write(_tool_file_path(tc.get("name") or "", tc.get("arguments"))):
                        wrote = True
        # Grok updates.jsonl (ACP events) — last resort if chat_history missing.
        elif ev.get("method") in ("session/update", "_x.ai/session/update"):
            upd = ((ev.get("params") or {}).get("update") or {})
            kind = upd.get("sessionUpdate")
            if kind == "user_message_chunk":
                # Chunked; counting here would over-count. Prefer chat_history.
                pass
            elif kind == "agent_message_chunk":
                text = ((upd.get("content") or {}).get("text") or "")
                chars += len(text)

    return turns, chars, wrote


def _dump_stdin(payload: dict) -> None:
    try:
        dump = Path.home() / ".cache" / "brain-hooks"
        dump.mkdir(parents=True, exist_ok=True)
        reason = _payload_get(payload, "reason", default="unknown")
        (dump / "stop.stdin.json").write_text(
            json.dumps(payload, indent=2)[:20000], encoding="utf-8"
        )
        (dump / f"stop.{reason}.stdin.json").write_text(
            json.dumps(payload, indent=2)[:20000], encoding="utf-8"
        )
        (dump / "stop.env").write_text(
            f"GROK_HOOK_EVENT={os.environ.get('GROK_HOOK_EVENT', '')}\n"
            f"GROK_SESSION_ID={os.environ.get('GROK_SESSION_ID', '')}\n",
            encoding="utf-8",
        )
    except OSError:
        pass


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    _dump_stdin(payload)

    # Never loop: if we already blocked and the model is stopping again, let it.
    # Claude: stop_hook_active. Grok: stopHookActive.
    if payload.get("stop_hook_active") or payload.get("stopHookActive"):
        return 0
    # peek is a one-question floating window, not a work session.
    if os.environ.get("PEEK") == "1":
        return 0
    if not VAULT.is_dir():
        return 0

    # Grok fires Stop at session end too (reason=shutdown/channel_closed).
    # Blocking that is ignored and would still set the mark. Only gate end_turn.
    # Claude typically omits reason or uses end_turn-like values; treat missing
    # as "gate this" so Claude's behaviour is unchanged.
    reason = _payload_get(payload, "reason", default="")
    if os.environ.get("GROK_HOOK_EVENT") or payload.get("hookEventName") == "stop":
        if reason and reason != "end_turn":
            return 0

    tpath = _payload_get(payload, "transcript_path", "transcriptPath")
    if not tpath:
        return 0

    sid = str(_payload_get(payload, "session_id", "sessionId", default="unknown"))
    mark = MARK_DIR / sid
    if mark.exists():
        return 0

    src = resolve_transcript(Path(tpath).expanduser())
    turns, chars, wrote = transcript_stats(src)
    try:
        dump = Path.home() / ".cache" / "brain-hooks"
        dump.mkdir(parents=True, exist_ok=True)
        (dump / "stop.stats.json").write_text(
            json.dumps({"transcript": str(src), "turns": turns, "chars": chars,
                        "wrote": wrote, "reason": reason, "sid": sid}),
            encoding="utf-8",
        )
    except OSError:
        pass

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
