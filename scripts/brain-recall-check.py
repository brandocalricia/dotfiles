#!/usr/bin/env python3
"""brain-recall-check — Stop hook backstop for Grok vault retrieval.

Grok 1.0.5 cannot inject notes on UserPromptSubmit. Retrieval is the model
choosing to call brain_search. When a turn clearly concerned the user's
projects/machines/config (same retrieve() scorer the MCP uses) and
brain_search was never called, block once with:

  you answered without searching the vault — search and reconsider.

Stays quiet when retrieve() is silent, when brain_search already ran this
turn, when Stop is not end_turn, and when stopHookActive is set (no loop).

Inherits retrieve()'s misses: a short prompt like "fix my qt theme" scores
too weak to fire. That is named, not papered over.
"""
from __future__ import annotations

import importlib.util
import json
import os
import sys
from pathlib import Path

VAULT = Path(os.environ.get("BRAIN_VAULT", Path.home() / "Documents" / "Brain"))
RETRIEVE_PY = Path.home() / "dotfiles" / "scripts" / "brain-retrieve.py"

REASON = (
    "you answered without searching the vault — search and reconsider.\n\n"
    "Stop hook (brain-recall-check): this turn was about the user's projects, "
    "machines, config, games, or history, but brain_search was never called. "
    "Call the brain_search MCP tool with the user's prompt verbatim, read what "
    "comes back, and answer again from their notes. Do not skip this because "
    "INDEX or memory already looks sufficient."
)


def _payload_get(payload: dict, *keys, default=None):
    for k in keys:
        v = payload.get(k)
        if v not in (None, ""):
            return v
    return default


def resolve_transcript(path: Path) -> Path:
    if path.name == "updates.jsonl":
        alt = path.with_name("chat_history.jsonl")
        if alt.exists():
            return alt
    return path


def load_retrieve():
    spec = importlib.util.spec_from_file_location("brain_retrieve", RETRIEVE_PY)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.retrieve


def _args(raw) -> dict:
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str):
        try:
            v = json.loads(raw)
            return v if isinstance(v, dict) else {}
        except ValueError:
            return {}
    return {}


def _texts(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for b in content:
            if isinstance(b, dict):
                parts.append(b.get("text") or "")
            elif isinstance(b, str):
                parts.append(b)
        return "\n".join(parts)
    return ""


def last_turn(path: Path) -> tuple[str, bool]:
    """(last real user prompt, brain_search called after it)."""
    prompt, searched = "", False
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError:
        return "", True  # can't tell → stay silent

    for line in lines:
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        t = ev.get("type")
        if t == "user" and not ev.get("synthetic_reason"):
            blob = _texts(ev.get("content")).strip()
            if not blob or blob.startswith("<"):
                continue
            if "prompt_index" in ev or not blob.lstrip().startswith("Caveat"):
                prompt = blob
                searched = False
        elif t == "assistant":
            for tc in ev.get("tool_calls") or []:
                if not isinstance(tc, dict):
                    continue
                name = (tc.get("name") or "").lower()
                args = _args(tc.get("arguments"))
                tool = str(args.get("tool_name") or "")
                if "brain_search" in name or "brain_search" in tool:
                    searched = True
        # Claude-shaped transcript (overlap month)
        msg = ev.get("message") or {}
        if msg:
            role = msg.get("role") or ""
            content = msg.get("content")
            if role == "user":
                blob = _texts(content).strip()
                if blob and not blob.startswith("<"):
                    prompt = blob
                    searched = False
            elif role == "assistant" and isinstance(content, list):
                for b in content:
                    if not isinstance(b, dict) or b.get("type") != "tool_use":
                        continue
                    name = str(b.get("name") or "")
                    inp = b.get("input") or {}
                    if "brain_search" in name or "brain_search" in str(inp.get("tool_name") or ""):
                        searched = True
    return prompt, searched


def _dump(payload: dict, extra: dict | None = None) -> None:
    try:
        dump = Path.home() / ".cache" / "brain-hooks"
        dump.mkdir(parents=True, exist_ok=True)
        (dump / "recall-check.stdin.json").write_text(
            json.dumps(payload, indent=2)[:20000], encoding="utf-8"
        )
        if extra is not None:
            (dump / "recall-check.stats.json").write_text(
                json.dumps(extra, indent=2), encoding="utf-8"
            )
    except OSError:
        pass


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    _dump(payload)

    if os.environ.get("BRAIN_RECALL_BENCH") == "1":
        return 0
    if os.environ.get("PEEK") == "1":
        return 0
    if payload.get("stop_hook_active") or payload.get("stopHookActive"):
        return 0

    reason = _payload_get(payload, "reason", default="")
    grok = bool(os.environ.get("GROK_HOOK_EVENT")) or payload.get("hookEventName") == "stop"
    if grok and reason and reason != "end_turn":
        return 0

    tpath = _payload_get(payload, "transcript_path", "transcriptPath")
    if not tpath:
        return 0
    src = resolve_transcript(Path(tpath).expanduser())
    prompt, searched = last_turn(src)
    concerned = False
    try:
        retrieve = load_retrieve()
        concerned = retrieve(prompt) is not None
    except Exception:
        concerned = False

    stats = {
        "transcript": str(src),
        "prompt_preview": (prompt or "")[:160],
        "searched": searched,
        "concerned": concerned,
        "reason": reason,
    }
    _dump(payload, stats)

    if searched or not concerned or not prompt:
        return 0

    # stopHookActive already prevents a loop on this same Stop. Next turn is
    # a new Stop with stopHookActive false, so a later skip still fires.
    print(json.dumps({"decision": "block", "reason": REASON}))
    return 0


def _prove() -> int:
    """Synthetic transcripts: fire on a vault turn with no search, quiet on math."""
    import tempfile

    def run(prompt: str, searched: bool) -> dict:
        hist = []
        hist.append({"type": "user", "prompt_index": 0,
                     "content": [{"type": "text", "text": prompt}]})
        if searched:
            hist.append({
                "type": "assistant",
                "content": "",
                "tool_calls": [{
                    "name": "use_tool",
                    "arguments": json.dumps({
                        "tool_name": "brain__brain_search",
                        "tool_input": {"query": prompt},
                    }),
                }],
            })
        else:
            hist.append({"type": "assistant", "content": "some answer"})
        td = Path(tempfile.mkdtemp(prefix="recall-check-"))
        p = td / "chat_history.jsonl"
        p.write_text("\n".join(json.dumps(e) for e in hist) + "\n", encoding="utf-8")
        payload = {
            "hookEventName": "stop",
            "reason": "end_turn",
            "transcriptPath": str(p),
            "sessionId": "prove-" + td.name,
            "stopHookActive": False,
        }
        proc = __import__("subprocess").run(
            [sys.executable, str(Path(__file__).resolve())],
            input=json.dumps(payload),
            text=True, capture_output=True, timeout=15,
            env={**os.environ, "GROK_HOOK_EVENT": "stop"},
        )
        out = (proc.stdout or "").strip()
        blocked = False
        reason = ""
        if out:
            try:
                data = json.loads(out)
                blocked = data.get("decision") == "block"
                reason = data.get("reason") or ""
            except json.JSONDecodeError:
                pass
        return {"blocked": blocked, "reason": reason, "stdout": out,
                "rc": proc.returncode, "prompt": prompt, "searched": searched}

    fire = run("is kimi cheaper?", searched=False)
    quiet_math = run("what's 17 * 43", searched=False)
    quiet_searched = run("is kimi cheaper?", searched=True)
    print("FIRE  vault prompt, no search:  "
          f"blocked={fire['blocked']}  rc={fire['rc']}")
    print("QUIET trivial math, no search:  "
          f"blocked={quiet_math['blocked']}  rc={quiet_math['rc']}")
    print("QUIET vault prompt, searched:   "
          f"blocked={quiet_searched['blocked']}  rc={quiet_searched['rc']}")
    ok = fire["blocked"] and "search and reconsider" in fire["reason"]
    ok = ok and not quiet_math["blocked"] and not quiet_searched["blocked"]
    print("PROVE", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--prove":
        try:
            sys.exit(_prove())
        except Exception as exc:
            print(f"PROVE FAIL: {exc}", file=sys.stderr)
            sys.exit(1)
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
