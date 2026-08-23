#!/usr/bin/env python3
"""
brain-retrieve — Claude Code UserPromptSubmit hook.

Searches the Obsidian vault on every prompt and injects the notes that actually
bear on it. This is what makes the vault work without anyone typing a command:
the user writes a normal prompt, and their own prior notes arrive with it.

Design constraints, in order of importance:
  1. Silent unless the match is strong. A wrong note is worse than no note —
     it pollutes context on every unrelated prompt.
  2. Fast. This runs before every single prompt; budget is ~200ms.
  3. Small. Capped hard, so a runaway match can't crowd out the real work.
"""
from __future__ import annotations

import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

VAULT = Path(os.environ.get("BRAIN_VAULT", Path.home() / "Documents" / "Brain"))

# Machine-written or archived areas: never retrieved as "what the user knows".
EXCLUDE = ("Claude/Sessions/", "Claude/Rollups/", "04-Archive/", "03-Resources/ChatHistory/")
SKIP_DIRS = {".git", ".obsidian", ".stfolder", ".trash"}

MAX_NOTES = 3       # plus at most one linked neighbour (see the graph hop)
MAX_CHARS = 2800
MIN_SCORE = 6  # below this the match is coincidental; stay quiet

STOP = set("""
a about above after again against all am an and any are aren as at be because been before being
below between both but by can cannot could couldn did didn do does doesn doing don down during
each few for from further had hadn has hasn have haven having he her here hers herself him himself
his how i if in into is isn it its itself let me more most mustn my myself no nor not of off on
once only or other ought our ours ourselves out over own same shan she should shouldn so some such
than that the their theirs them themselves then there these they this those through to too under
until up very was wasn we were weren what when where which while who whom why with won would
wouldn you your yours yourself yourselves get got make made use used using want need know think
like just also them please help thing things way ways lot really actually maybe okay yeah
file files code run running add added new now then here there
""".split())

# Verbs describing the *task* rather than the *topic*. Without these, "write a
# python script" retrieves every note whose headings happen to say "write".
STOP |= set("""
write writing wrote create creating build building make making implement implementing
refactor refactoring debug debugging fix fixing update updating install installing
setup script scripts parse parsing explain check checking test testing deploy
change changes edit editing remove delete rename move copy show tell give
""".split())

# Prompts that are pure mechanics — retrieval would only add noise.
MECHANICAL = re.compile(
    r"^\s*(ls|cd|cat|git|npm|pip|sudo|systemctl|grep|find|mkdir|rm|cp|mv|chmod|curl)\b"
    r"|^\s*(yes|no|ok|okay|sure|thanks|thank you|continue|go|do it|proceed|stop|nvm|nevermind)\s*[.!]?\s*$",
    re.I,
)


def stem(w: str) -> str:
    """Crude, deliberately conservative stemmer.

    Matching below is substring-based, so "note" already finds "notes" — but not
    the reverse. Reducing the *query* term to its stem fixes that direction,
    which is most of the misses: the user types "vaults"/"retrieving" and the
    note says "vault"/"retrieve".
    """
    if w.endswith("ies") and len(w) > 5:
        return w[:-3] + "y"
    if w.endswith("ing") and len(w) > 6:
        return w[:-3]
    if w.endswith("ed") and len(w) > 5:
        return w[:-2]
    if w.endswith("s") and not w.endswith(("ss", "us", "is")) and len(w) > 4:
        return w[:-1]
    return w


def terms(prompt: str) -> set[str]:
    words = re.findall(r"[A-Za-z][A-Za-z0-9'-]{2,}", prompt.lower())
    return {stem(w) for w in words if len(w) >= 4 and w not in STOP}


ALIAS_RE = re.compile(r"^aliases:\s*(.+)$", re.M)
LINK_RE = re.compile(r"\[\[([^\]|#]+)")


def aliases(text: str) -> str:
    """The note's aliases, as one lowercase blob to substring-match against.

    An alias is the user's own second name for a note — the whole point is that
    they'll type that name instead of the filename. Not matching on it is the
    single most avoidable miss.
    """
    if not text.startswith("---"):
        return ""
    end = text.find("\n---", 3)
    fm = text[:end] if end != -1 else text[:600]
    out = []
    for m in ALIAS_RE.finditer(fm):
        out.append(m.group(1))
    # YAML list form: `aliases:` followed by `  - foo` lines.
    for m in re.finditer(r"^aliases:\s*$((?:\n\s+-\s*.+)+)", fm, re.M):
        out.append(m.group(1))
    return re.sub(r"[\[\]\"',-]", " ", " ".join(out)).lower()


def notes() -> list[Path]:
    out = []
    for dirpath, dirnames, filenames in os.walk(VAULT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith(".md"):
                continue
            p = Path(dirpath) / fn
            rel = p.relative_to(VAULT).as_posix()
            if rel.startswith(EXCLUDE):
                continue
            out.append(p)
    return out


# Lines that are pure navigation — never worth spending excerpt budget on.
NAV_LINE = re.compile(r"^\s*(-\s*)?\[\[[^\]]+\]\]\s*$|^\s*#{1,6}\s*(related|see also|links?|backlinks?|maintenance|sources?)\b", re.I)
# Sections that exist to say what the note is *not* about.
ANTI_SECTION = re.compile(r"doesn'?t cover|not covered|out of scope|todo|maintenance", re.I)


def excerpt(text: str, hits: set[str], limit: int = 700) -> str:
    """The densest run of substantive lines mentioning the query terms."""
    # Drop the YAML frontmatter block entirely — its keys match query terms and
    # make for a useless excerpt ("name: …", "description: …").
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            text = text[end + 4 :]
    lines = [
        ln for ln in text.splitlines()
        if ln.strip() and not ln.startswith("---") and not NAV_LINE.match(ln)
    ]
    if not lines:
        return ""

    best_i, best_score = 0, -1
    for i, ln in enumerate(lines):
        low = ln.lower()
        if ANTI_SECTION.search(low):
            continue
        # Score a small window so we land on a dense passage, not a lone mention.
        window = " ".join(lines[i : i + 4]).lower()
        s = sum(window.count(t) for t in hits)
        # Prefer earlier sections; the top of a note is usually its thesis.
        s -= i * 0.02
        if s > best_score:
            best_i, best_score = i, s

    start = max(0, best_i - 1)
    out, total = [], 0
    for ln in lines[start : start + 14]:
        if ANTI_SECTION.search(ln.lower()):
            break
        if total + len(ln) > limit:
            break
        out.append(ln)
        total += len(ln)
    return "\n".join(out).rstrip()


def _dump_stdin(payload: dict) -> None:
    try:
        dump = Path.home() / ".cache" / "brain-hooks"
        dump.mkdir(parents=True, exist_ok=True)
        (dump / "userpromptsubmit.stdin.json").write_text(
            json.dumps(payload, indent=2)[:20000], encoding="utf-8"
        )
        (dump / "userpromptsubmit.env").write_text(
            f"GROK_HOOK_EVENT={os.environ.get('GROK_HOOK_EVENT', '')}\n"
            f"CLAUDE_PROJECT_DIR={os.environ.get('CLAUDE_PROJECT_DIR', '')}\n"
            f"GROK_SESSION_ID={os.environ.get('GROK_SESSION_ID', '')}\n",
            encoding="utf-8",
        )
    except OSError:
        pass


def _prompt_from_payload(payload: dict) -> str:
    """Claude: {prompt: str}. Grok: camelCase, sometimes nested."""
    for key in ("prompt", "promptText", "text", "userPrompt"):
        v = payload.get(key)
        if isinstance(v, str) and v.strip():
            return v.strip()
    # Grok UserPromptSubmit may nest the text under content/message.
    for key in ("content", "message"):
        v = payload.get(key)
        if isinstance(v, str) and v.strip():
            return v.strip()
        if isinstance(v, dict):
            inner = v.get("content") or v.get("text") or v.get("prompt")
            if isinstance(inner, str) and inner.strip():
                return inner.strip()
            if isinstance(inner, list):
                parts = []
                for b in inner:
                    if isinstance(b, dict) and b.get("type") in (None, "text"):
                        parts.append(b.get("text") or "")
                    elif isinstance(b, str):
                        parts.append(b)
                joined = " ".join(parts).strip()
                if joined:
                    return joined
    return ""


STATUS_PATH = Path.home() / ".cache" / "brain-hooks" / "retrieval-status.json"


def write_heartbeat(*, prompt: str, ctx: str | None, harness: str) -> None:
    """Record whether retrieval ran and whether automatic injection can work.

    Grok 1.0.5 ignores UserPromptSubmit stdout/stderr/exit codes (probed
    2026-08-23). Claude consumes hookSpecificOutput. Do not mark Grok as
    confirmed just because the hook found notes.
    """
    try:
        STATUS_PATH.parent.mkdir(parents=True, exist_ok=True)
        grok = harness == "grok"
        STATUS_PATH.write_text(json.dumps({
            "ts": __import__("datetime").datetime.now(
                __import__("datetime").timezone.utc
            ).isoformat(),
            "harness": harness,
            "prompt_preview": (prompt or "")[:120],
            "matched": bool(ctx),
            "nchars": len(ctx or ""),
            "automatic_injection": "degraded" if grok else "working",
            "confirmed": (not grok),
        }, indent=2) + "\n", encoding="utf-8")
    except OSError:
        pass


def retrieve(prompt: str) -> str | None:
    """Search the vault. Returns the formatted context block, or None if silent.

    This is the single ranking implementation. The UserPromptSubmit hook, the
    MCP server, and any other caller must go through here — do not fork it.
    """
    prompt = (prompt or "").strip()
    if len(prompt) < 12 or MECHANICAL.search(prompt) or not VAULT.is_dir():
        return None
    q = terms(prompt)
    if len(q) < 2:
        return None

    scores: dict[Path, int] = defaultdict(int)
    weak: dict[Path, int] = {}          # every note that matched at all
    matched: dict[Path, set[str]] = defaultdict(set)
    bodies: dict[Path, str] = {}
    outlinks: dict[Path, set[str]] = {}  # note -> link targets it names
    by_name: dict[str, Path] = {}        # lowercase title/alias -> note

    for p in notes():
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        low = text.lower()
        title = p.stem.lower()
        alias = aliases(text)
        headings = " ".join(re.findall(r"^#{1,3} .*", text, re.M)).lower()

        outlinks[p] = {m.strip().lower() for m in LINK_RE.findall(text)}
        by_name.setdefault(title, p)
        for a in alias.split():
            by_name.setdefault(a, p)

        score, in_title, head_terms = 0, False, 0
        for t in q:
            in_name = t in title or t in alias
            in_head = t in headings
            n = low.count(t)
            if not (in_name or in_head or n):
                continue
            matched[p].add(t)
            in_title |= in_name
            head_terms += in_head
            score += 8 * in_name + 3 * in_head + min(n, 4)
        if score:
            weak[p] = score
            bodies[p] = text
        # A single shared word is a coincidence; two or more is a topic. Beyond
        # that the note must be *about* the question: its filename matches, or
        # two separate query terms hit its headings. One generic word in one
        # heading is how "parse a csv" drags in the publishing pipeline note.
        if len(matched[p]) >= 2 and (in_title or head_terms >= 2):
            scores[p] = score

    if not scores:
        return None
    ranked = sorted(scores.items(), key=lambda kv: -kv[1])[:MAX_NOTES]
    top = ranked[0][1]
    # Keep runners-up only if they're in the same league as the best match;
    # a far-behind third note is filler, not context.
    ranked = [(p, s) for p, s in ranked if s >= MIN_SCORE and s >= top * 0.5]
    if not ranked:
        return None

    # One graph hop. A vault is a graph, not a pile of documents: the note that
    # explains the answer is often the one the best match *links to*, under a
    # name the prompt never used. So take the top hit's neighbourhood — what it
    # links to, and what links to it — and admit the strongest neighbour that
    # also matched the query at all. The query-match floor is what keeps this
    # from dragging in an arbitrary neighbour and violating constraint #1.
    best = ranked[0][0]
    chosen = {p for p, _ in ranked}
    names = {best.stem.lower()} | set(aliases(bodies[best]).split())
    neigh = {by_name[t] for t in outlinks.get(best, ()) if t in by_name}
    neigh |= {p for p, links in outlinks.items() if links & names}
    cands = [
        (weak[p], p) for p in neigh
        if p not in chosen and weak.get(p, 0) >= 3
    ]
    if cands:
        cands.sort(reverse=True)
        ranked.append((cands[0][1], cands[0][0]))
        linked = cands[0][1]
    else:
        linked = None

    if os.environ.get("BRAIN_RETRIEVE_DEBUG"):
        for p, s in ranked:
            print(f"[debug] {s:4d}  {p.relative_to(VAULT)}  {sorted(matched[p])}", file=sys.stderr)

    parts = [
        "# From your vault (auto-retrieved, ~/Documents/Brain)",
        "",
        "These are the user's **own notes** matching this prompt. Prefer them over general",
        "knowledge, cite them by path when you use them, and say so if they contradict you.",
        "If they're irrelevant to what was actually asked, ignore them silently.",
        "",
    ]
    for p, s in ranked:
        rel = p.relative_to(VAULT).as_posix()
        via = " — linked from the note above" if p is linked else ""
        parts.append(f"## `{rel}`{via}")
        ex = excerpt(bodies[p], matched[p])
        if ex:
            parts.append(ex)
        parts.append("")

    return "\n".join(parts)[:MAX_CHARS]


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    _dump_stdin(payload)
    prompt = _prompt_from_payload(payload)
    grok = bool(os.environ.get("GROK_HOOK_EVENT"))
    harness = "grok" if grok else "claude"
    ctx = retrieve(prompt)
    write_heartbeat(prompt=prompt, ctx=ctx, harness=harness)
    if not ctx:
        return 0
    event_name = (
        os.environ.get("GROK_HOOK_EVENT")
        or payload.get("hookEventName")
        or payload.get("hook_event_name")
        or "UserPromptSubmit"
    )
    # Claude consumes hookSpecificOutput.additionalContext. Grok 1.0.5's
    # documented UserPromptSubmit is observe-only (stdout ignored). Emit the
    # Claude schema always so overlap still works; also write a side copy so
    # we can prove whether Grok ingested it.
    out = {
        "hookSpecificOutput": {
            "hookEventName": event_name if event_name != "user_prompt_submit" else "UserPromptSubmit",
            "additionalContext": ctx,
        }
    }
    # Some Grok events (Stop) also honor top-level additionalContext. Harmless extra.
    out["additionalContext"] = ctx
    blob = json.dumps(out)
    try:
        dump = Path.home() / ".cache" / "brain-hooks"
        dump.mkdir(parents=True, exist_ok=True)
        (dump / "userpromptsubmit.stdout.json").write_text(blob, encoding="utf-8")
        (dump / "userpromptsubmit.context.md").write_text(ctx, encoding="utf-8")
    except OSError:
        pass
    print(blob)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # A retrieval failure must never block the user's prompt.
        sys.exit(0)
