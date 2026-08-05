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

MAX_NOTES = 3
MAX_CHARS = 2200
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


def terms(prompt: str) -> set[str]:
    words = re.findall(r"[A-Za-z][A-Za-z0-9'-]{2,}", prompt.lower())
    return {w for w in words if len(w) >= 4 and w not in STOP}


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


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    prompt = (payload.get("prompt") or "").strip()

    if len(prompt) < 12 or MECHANICAL.search(prompt) or not VAULT.is_dir():
        return 0
    q = terms(prompt)
    if len(q) < 2:
        return 0

    scores: dict[Path, int] = defaultdict(int)
    matched: dict[Path, set[str]] = defaultdict(set)
    bodies: dict[Path, str] = {}

    for p in notes():
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        low = text.lower()
        stem = p.stem.lower()
        headings = " ".join(re.findall(r"^#{1,3} .*", text, re.M)).lower()

        score, in_title, head_terms = 0, False, 0
        for t in q:
            in_name = t in stem
            in_head = t in headings
            n = low.count(t)
            if not (in_name or in_head or n):
                continue
            matched[p].add(t)
            in_title |= in_name
            head_terms += in_head
            score += 8 * in_name + 3 * in_head + min(n, 4)
        # A single shared word is a coincidence; two or more is a topic. Beyond
        # that the note must be *about* the question: its filename matches, or
        # two separate query terms hit its headings. One generic word in one
        # heading is how "parse a csv" drags in the publishing pipeline note.
        if len(matched[p]) >= 2 and (in_title or head_terms >= 2):
            scores[p] = score
            bodies[p] = text

    if not scores:
        return 0
    ranked = sorted(scores.items(), key=lambda kv: -kv[1])[:MAX_NOTES]
    top = ranked[0][1]
    # Keep runners-up only if they're in the same league as the best match;
    # a far-behind third note is filler, not context.
    ranked = [(p, s) for p, s in ranked if s >= MIN_SCORE and s >= top * 0.5]
    if not ranked:
        return 0

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
        parts.append(f"## `{rel}`")
        ex = excerpt(bodies[p], matched[p])
        if ex:
            parts.append(ex)
        parts.append("")

    ctx = "\n".join(parts)[:MAX_CHARS]
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": ctx,
        }
    }))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # A retrieval failure must never block the user's prompt.
        sys.exit(0)
