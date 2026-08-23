#!/usr/bin/env python3
"""brain-recall-bench — measure Grok 1.0.5 vault-search recall.

Grok has no per-prompt injection (probed). Retrieval is the model choosing to
call brain_search or auto-invoke /brain. This script is the number that decides
whether vault work can leave Claude Code.

Each case is a FRESH grok -p session. Follow-ups are a setup turn then --resume.
Nothing here tells the model to search; the prompt is the prompt.

Metrics
  searched     brain_search (MCP use_tool) or /brain skill file was read
  right_note   an expected note path appeared in a tool result or a read
  used         the final answer cites an expected note or a vault-specific fact
  hard recall  searched AND right_note on the hard subset
  false-pos    searched on a negative control (searching would be wrong)

Usage
  brain-recall-bench.py --local              # retrieve() coverage only
  brain-recall-bench.py --smoke              # 3 live sessions (easy/hard/neg)
  brain-recall-bench.py --run [--jobs N]
  brain-recall-bench.py --report [DIR]
"""
from __future__ import annotations

import argparse
import concurrent.futures
import importlib.util
import json
import os
import re
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
DOTFILES = HOME / "dotfiles"
RETRIEVE_PY = DOTFILES / "scripts" / "brain-retrieve.py"
GROK_BIN = Path(os.environ.get("GROK_BIN", HOME / ".grok" / "bin" / "grok"))
CONTEXT_SH = DOTFILES / "scripts" / "claude-brain-context.sh"
VAULT = HOME / "Documents" / "Brain"
OUT_ROOT = HOME / ".cache" / "brain-hooks" / "recall-bench"
CWD = Path("/tmp/grok-recall-bench")
SESSIONS = HOME / ".grok" / "sessions"

# Bench sessions must not mutate the vault, home, or this repo.
DISALLOWED = ",".join((
    "write",
    "search_replace",
    "image_gen",
    "image_edit",
    "image_to_video",
    "reference_to_video",
))

SKILL_PATHS = (
    str(HOME / ".claude" / "commands" / "brain.md"),
    str(HOME / ".grok" / "skills" / "brain" / "SKILL.md"),
)


# ── cases ──────────────────────────────────────────────────────────────────
# hard: short, generic-looking, follow-up, or vault-contradicts-common-advice.
# negative: searching the vault would be wrong.
# expect_notes: filename stems a correct answer would land on.
# expect_facts: vault-specific strings general knowledge would not produce.

def C(id, prompt, *, hard=False, negative=False, notes=(), facts=(),
      tags=(), setup=None):
    return {
        "id": id,
        "prompt": prompt,
        "hard": hard,
        "negative": negative,
        "expect_notes": list(notes),
        "expect_facts": list(facts),
        "tags": list(tags),
        "setup": setup,
    }


CASES: list[dict] = [
    # ── HARD: short / generic-looking ────────────────────────────────────
    C("waybar-blank", "why is waybar blank again",
      hard=True, tags=("short", "generic"),
      notes=("waybar_pango_glyphs.md",),
      facts=("pango", "fontawesome", "material design", "U+F0")),
    C("qt-theme", "fix my qt theme",
      hard=True, tags=("short", "generic"),
      notes=("hyprland_qt_theme.md",),
      facts=("qgnomeplatform", "adwaita-qt", "breeze", "qt_qpa_platformtheme")),
    C("dolphin-unreadable", "dolphin is unreadable",
      hard=True, tags=("short", "generic"),
      notes=("hyprland_qt_theme.md",),
      facts=("black-on-black", "breeze", "qgnomeplatform", "kdeglobals")),
    C("bar-icons-followup", "the icons in the bar disappeared again",
      hard=True, tags=("short", "followup", "generic"),
      setup="I'm looking at my Hyprland config on the desktop",
      notes=("waybar_pango_glyphs.md",),
      facts=("pango", "nerd font", "fontawesome", "material design")),
    C("geode-no-load", "geode didn't load",
      hard=True, tags=("short",),
      notes=("geometry_dash_geode.md",),
      facts=("xinput1_4", "winedlloverrides", "silently")),
    C("gd-mods-button", "mods button missing in gd",
      hard=True, tags=("short", "generic"),
      notes=("geometry_dash_geode.md",),
      facts=("xinput1_4", "geode", "winedlloverrides")),
    C("upload-4meg", "my upload is only 4 meg",
      hard=True, tags=("short", "generic"),
      notes=("tmobile_gaming_net.md",),
      facts=("4200kbit", "23mbit", "cake", "eno1")),
    C("rusty-black-bar", "rusty's has a black bar",
      hard=True, tags=("short",),
      notes=("rusty_retirement_hyprland.md",),
      facts=("opaque black", "gamescope", "unavoidable", "proton")),
    C("screen-wont-sleep", "screen won't sleep",
      hard=True, tags=("short", "generic"),
      notes=("caffeine_toggle.md",),
      facts=("hypridle", "idle inhibitor", "ignore_inhibit", "caffeine")),
    C("f6-dead", "F6 does nothing in megabonk",
      hard=True, tags=("short",),
      notes=("bonkscanner_hookfree.md", "BonkScanner-Megabonk-Setup.md"),
      facts=("cmd.txt", "bonkpatch", "hook-free", "wh_keyboard")),

    # ── HARD: vault contradicts general knowledge / common advice ────────
    C("kimi-cheaper", "is kimi cheaper?",
      hard=True, tags=("contradict", "short"),
      notes=("Kimi-K3-Decision.md", "kimi_k3_overflow.md"),
      facts=("8×", "8x", "$20", "subscription", "cck", "155")),
    C("switch-kimi", "should I switch to kimi",
      hard=True, tags=("contradict",),
      notes=("Kimi-K3-Decision.md", "kimi_k3_overflow.md"),
      facts=("do not switch", "overflow", "cck", "8×", "8x", "$20")),
    C("encrypt-disk", "encrypt the disk already",
      hard=True, tags=("contradict",),
      notes=("INDEX.md",),
      facts=("declined", "not going to be targeted", "luks")),
    C("remove-cake", "remove cake it's throttling me",
      hard=True, tags=("contradict",),
      notes=("tmobile_gaming_net.md",),
      facts=("23mbit", "do not remove", "bufferbloat", "4200kbit")),
    C("cancel-claude", "should I cancel claude",
      hard=True, tags=("contradict",),
      notes=("Grok-Migration-Plan.md", "Leaving-Claude-2026-08.md"),
      facts=("do not cancel", "not ready", "recall", "2026-09-06", "partially restored")),
    C("bakkes-online", "can I use bakkes online",
      hard=True, tags=("contradict",),
      notes=("bakkesmod_training.md",),
      facts=("-noeac", "offline", "eac", "rl-train")),
    C("cryptid-balatro", "cryptid for balatro?",
      hard=True, tags=("contradict",),
      notes=("balatro_mods.md", "Balatro-Mods-Setup.md"),
      facts=("all in jest", "dropped", "cryptid")),
    C("samrewritten", "samrewritten for megabonk achievements",
      hard=True, tags=("contradict",),
      notes=("megabonk_unlock.md",),
      facts=("never needed", "natively", "139/139", "retroactively")),
    C("hypridle-sigstop", "just SIGSTOP hypridle for caffeine",
      hard=True, tags=("contradict",),
      notes=("caffeine_toggle.md",),
      facts=("not sigstop", "wayland connection", "pkill", "deaf")),
    C("first-principles-note", "write a new vault note about first principles",
      hard=True, tags=("contradict", "trap"),
      notes=("INDEX.md", "Vault-Health-Tooling.md"),
      facts=("never generate", "haven't engaged", "unwritten", "do not write")),

    # ── HARD: follow-ups mid-conversation ────────────────────────────────
    C("samrewritten-followup", "did steam achievements need samrewritten",
      hard=True, tags=("followup", "contradict"),
      setup="I'm looking at the megabonk save files on the storage drive",
      notes=("megabonk_unlock.md",),
      facts=("never needed", "natively", "139", "retroactively")),
    C("peek-restart-followup", "what's the official restart",
      hard=True, tags=("followup", "short"),
      setup="working on peek again, the floating assistant",
      notes=("peek_assistant.md", "INDEX.md"),
      facts=("pkill -f peek", "super+a")),
    C("caffeine-youtube-followup",
      "youtube is playing, I still want the screen to blank when I walk away",
      hard=True, tags=("followup",),
      setup="looking at the hypridle timers on the desktop",
      notes=("caffeine_toggle.md",),
      facts=("idle inhibitor", "ignore_inhibit", "zwp_idle")),
    C("autoclick-bind", "autoclicker bind does nothing",
      hard=True, tags=("generic",),
      notes=("ydotool_autoclicker.md",),
      facts=("~/.local/bin", "hyprland", "path", "super+f9")),
    C("tmobile-shaper", "T-Mobile CAKE shaper",
      hard=True, tags=("retrieve-miss",),
      notes=("tmobile_gaming_net.md",),
      facts=("23mbit", "eno1", "bufferbloat", "g5ar")),

    # ── EASY: names the project / tool clearly ───────────────────────────
    C("megabonk-crypto", "megabonk save encryption",
      tags=("easy", "anecdote"),
      notes=("megabonk_unlock.md",),
      facts=("aes-256-cbc", "lethalm", "progression.json")),
    C("bonkscanner-how", "how does bonkscanner work on this machine",
      tags=("easy",),
      notes=("BonkScanner-Megabonk-Setup.md", "bonkscanner_hookfree.md"),
      facts=("hook-free", "cmd.txt", "wh_keyboard", "wine")),
    C("balatro-laptop", "balatro mods reinstall on laptop",
      tags=("easy",),
      notes=("balatro_mods.md", "Balatro-Mods-Setup.md"),
      facts=("setup-balatro-mods.sh", "winedlloverrides", "profile 2", "lovely")),
    C("rusty-setup", "rusty retirement setup",
      tags=("easy",),
      notes=("rusty_retirement_hyprland.md",),
      facts=("gamescope", "rusty-bar-watch", "addreserved", "2666510")),
    C("ydotool-binds", "ydotool autoclicker binds",
      tags=("easy",),
      notes=("ydotool_autoclicker.md",),
      facts=("super+f9", "100 cps", "-d 5", "ydotoold")),
    C("caffeine-how", "caffeine toggle how it works",
      tags=("easy",),
      notes=("caffeine_toggle.md",),
      facts=("hypridle", "pkill", "not sigstop", "caffeine.on")),
    C("peek-super-a", "peek SUPER+A how it works",
      tags=("easy",),
      notes=("peek_assistant.md",),
      facts=("claude -p", "super+a", "~/code/peek", "stream-json")),
    C("grok-migration", "grok migration status",
      tags=("easy",),
      notes=("Grok-Migration-Plan.md",),
      facts=("degraded", "do not cancel", "1.0.5", "brain_search")),
    C("vault-doctor", "vault doctor what does it do",
      tags=("easy",),
      notes=("vault_health_doctor.md", "Vault-Health-Tooling.md"),
      facts=("brain-doctor", "10,769", "unlink", "sunday")),
    C("geode-launchopt", "geometry dash geode launch option",
      tags=("easy",),
      notes=("geometry_dash_geode.md",),
      facts=("xinput1_4", "winedlloverrides", "322170")),
    C("kimi-cck", "kimi cck launcher",
      tags=("easy",),
      notes=("kimi_k3_overflow.md", "Kimi-K3-Decision.md"),
      facts=("cck", "moonshot", "settings.json", "overflow")),
    C("fastfetch-logo", "foot fastfetch logo wrapping",
      tags=("easy",),
      notes=("project_fastfetch-tiling.md",),
      facts=("trapwinch", "logo-position", "82", "du-logo")),
    C("bakkes-rltrain", "BakkesMod rl-train",
      tags=("easy",),
      notes=("bakkesmod_training.md",),
      facts=("rl-train", "-noeac", "wine64", "offline")),
    C("qt-named", "Hyprland Qt theme dolphin",
      tags=("easy",),
      notes=("hyprland_qt_theme.md",),
      facts=("breeze", "qgnomeplatform", "adwaita-qt")),
    C("waybar-named", "waybar pango glyphs blank",
      tags=("easy",),
      notes=("waybar_pango_glyphs.md",),
      facts=("pango", "fontawesome", "material design")),
    C("dotfiles-sync", "how does my dotfiles sync work",
      tags=("easy",),
      notes=("project_dotfiles_workflow.md",),
      facts=("dotfiles-sync", "15 min", "pull --rebase", "stow")),
    C("never-gdm", "never touch gdm display manager",
      tags=("easy",),
      notes=("feedback_display_manager.md",),
      facts=("gdm", "sddm", "locked", "exclude=gdm")),
    C("megabonk-mods", "megabonk bepinex mods launch option",
      tags=("easy",),
      notes=("megabonk_unlock.md",),
      facts=("winhttp", "bepinex", "winedlloverrides", "megamod")),
    C("peek-restart", "pkill -f peek restart",
      tags=("easy",),
      notes=("peek_assistant.md", "INDEX.md"),
      facts=("pkill -f peek", "super+a")),
    C("cck-overflow", "cck overflow launcher",
      tags=("easy",),
      notes=("kimi_k3_overflow.md",),
      facts=("cck", "moonshot", "overflow", "settings.json")),

    # ── NEGATIVE CONTROLS: searching would be wrong ──────────────────────
    C("neg-math", "what's 17 * 43", negative=True, tags=("neg",)),
    C("neg-gil", "explain python's GIL", negative=True, tags=("neg",)),
    C("neg-tcp", "difference between TCP and UDP", negative=True, tags=("neg",)),
    C("neg-regex", "regex for email validation", negative=True, tags=("neg",)),
    C("neg-monad", "what is a monad", negative=True, tags=("neg",)),
    C("neg-temp", "convert 72 fahrenheit to celsius", negative=True, tags=("neg",)),
    C("neg-haiku", "write a haiku about rain", negative=True, tags=("neg",)),
    C("neg-quicksort", "how does quicksort work", negative=True, tags=("neg",)),
    C("neg-proof", "prove that 1+1=2 from peano axioms", negative=True, tags=("neg",)),
    C("neg-france", "what's the capital of france", negative=True, tags=("neg",)),
]


# ── retrieve() ─────────────────────────────────────────────────────────────

def load_retrieve():
    spec = importlib.util.spec_from_file_location("brain_retrieve", RETRIEVE_PY)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def notes_from_ctx(ctx: str | None) -> list[str]:
    if not ctx:
        return []
    out = []
    for line in ctx.splitlines():
        if line.startswith("## `"):
            out.append(line[4:].split("`")[0])
    return out


def stem_match(path: str, expect: list[str]) -> bool:
    low = path.lower()
    base = Path(path).name.lower()
    for e in expect:
        el = e.lower()
        if el in low or el in base or Path(el).stem.lower() in Path(base).stem.lower():
            return True
    return False


# ── transcript parsing ─────────────────────────────────────────────────────

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


def parse_history(path: Path, scored_prompt: str) -> dict:
    """Walk chat_history.jsonl. Score from the LAST matching user prompt onward."""
    empty = {
        "searched": False,
        "skill": False,
        "mcp": False,
        "memory_search": False,
        "grep_vault": False,
        "tools": [],
        "note_hits": [],
        "answer": "",
        "n_assistant": 0,
    }
    if not path.is_file():
        return empty

    events = []
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        try:
            events.append(json.loads(line))
        except ValueError:
            continue

    start = 0
    target = scored_prompt.strip()
    for i, ev in enumerate(events):
        if ev.get("type") != "user" or ev.get("synthetic_reason"):
            continue
        blob = _texts(ev.get("content"))
        if target and target in blob:
            start = i

    tools: list[str] = []
    note_hits: list[str] = []
    skill = mcp = mem = grep = False
    answers: list[str] = []

    def consider_blob(blob: str):
        nonlocal note_hits
        for m in re.finditer(r"(?:Documents/Brain/|Brain/)([^\s`\"']+\.md)", blob):
            note_hits.append(m.group(0))
        for m in re.finditer(r"`([^`]+\.md)`", blob):
            note_hits.append(m.group(1))

    for ev in events[start:]:
        t = ev.get("type")
        if t == "assistant":
            answers.append(_texts(ev.get("content")))
            for tc in ev.get("tool_calls") or []:
                if not isinstance(tc, dict):
                    continue
                name = tc.get("name") or ""
                args = _args(tc.get("arguments"))
                tools.append(name)
                joined = json.dumps(args, default=str).lower()
                if name == "use_tool" and "brain_search" in (
                    str(args.get("tool_name") or "") + joined
                ):
                    mcp = True
                if name == "search_tool" and "brain" in joined:
                    # schema lookup, not yet a search — still the brain path
                    pass
                if name == "memory_search":
                    mem = True
                fp = str(args.get("target_file") or args.get("path") or "")
                if any(fp.endswith(s) or s in fp for s in SKILL_PATHS) or (
                    fp.endswith("brain.md") and "commands" in fp
                ):
                    skill = True
                if name == "run_terminal_command":
                    cmd = str(args.get("command") or "")
                    if "Documents/Brain" in cmd or "~/Documents/Brain" in cmd:
                        grep = True
                consider_blob(joined)
                if fp.endswith(".md"):
                    note_hits.append(fp)
        elif t == "tool_result":
            consider_blob(_texts(ev.get("content")))

    searched = mcp or skill
    return {
        "searched": searched,
        "skill": skill,
        "mcp": mcp,
        "memory_search": mem,
        "grep_vault": grep,
        "tools": tools,
        "note_hits": sorted(set(note_hits)),
        "answer": "\n".join(a for a in answers if a.strip()),
        "n_assistant": len(answers),
    }


def used_vault(answer: str, notes: list[str], facts: list[str]) -> bool:
    low = answer.lower()
    for n in notes:
        if n.lower() in low or Path(n).stem.lower().replace("_", "-") in low.replace("_", "-"):
            return True
    for f in facts:
        if f.lower() in low:
            return True
    return False


def right_note(note_hits: list[str], expect: list[str], answer: str) -> bool:
    if not expect:
        return False
    for h in note_hits:
        if stem_match(h, expect):
            return True
    # cited in the answer even if the parser missed the tool result
    low = answer.lower()
    for e in expect:
        if e.lower() in low:
            return True
    return False


# ── grok runner ────────────────────────────────────────────────────────────

def refresh_context() -> None:
    if not CONTEXT_SH.is_file():
        return
    subprocess.run(
        [str(CONTEXT_SH)],
        input='{"source":"startup","hookEventName":"session_start"}',
        text=True,
        env={**os.environ, "GROK_HOOK_EVENT": "session_start"},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=20,
        check=False,
    )


def grok_cmd(prompt: str, *, resume: str | None = None) -> list[str]:
    cmd = [
        str(GROK_BIN),
        "-p", prompt,
        "--cwd", str(CWD),
        "--output-format", "json",
        "--always-approve",
        "--verbatim",
        "--no-auto-update",
        "--disable-web-search",
        "--no-subagents",
        "--max-turns", "12",
        "--disallowed-tools", DISALLOWED,
    ]
    if resume:
        cmd.extend(["--resume", resume])
    return cmd


def run_one(case: dict, timeout: int) -> dict:
    CWD.mkdir(parents=True, exist_ok=True)
    env = {
        **os.environ,
        "BRAIN_RECALL_BENCH": "1",
        "GROK_DISABLE_AUTOUPDATER": "1",
    }
    started = time.time()
    session_id = None
    setup_text = ""
    err = ""

    def invoke(prompt: str, resume=None):
        p = subprocess.run(
            grok_cmd(prompt, resume=resume),
            cwd=str(CWD),
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        out = p.stdout.strip()
        data = {}
        # json format is one object, sometimes pretty-printed, sometimes
        # preceded by a warning line.
        try:
            data = json.loads(out)
        except json.JSONDecodeError:
            start = out.find("{")
            end = out.rfind("}")
            if start != -1 and end > start:
                try:
                    data = json.loads(out[start:end + 1])
                except json.JSONDecodeError:
                    data = {}
        if not isinstance(data, dict):
            data = {}
        return p, data, out, p.stderr[-4000:]

    try:
        if case.get("setup"):
            p1, d1, _, e1 = invoke(case["setup"])
            session_id = d1.get("sessionId")
            setup_text = d1.get("text") or ""
            if not session_id:
                err = f"setup had no sessionId rc={p1.returncode} stderr={e1[-500:]}"
            p2, d2, raw, e2 = invoke(case["prompt"], resume=session_id)
            text = d2.get("text") or ""
            session_id = d2.get("sessionId") or session_id
            rc = p2.returncode
            err = err or (e2[-800:] if p2.returncode else "")
        else:
            p, d, raw, e = invoke(case["prompt"])
            text = d.get("text") or ""
            session_id = d.get("sessionId")
            rc = p.returncode
            err = e[-800:] if p.returncode else ""
    except subprocess.TimeoutExpired:
        rc, text, err = 124, "", f"timeout after {timeout}s"
    except Exception as exc:
        rc, text, err = 1, "", f"{type(exc).__name__}: {exc}"

    hist = Path()
    if session_id:
        # ~/.grok/sessions/<urlencoded-cwd>/<id>/chat_history.jsonl
        encoded = str(CWD).replace("/", "%2F")
        cand = SESSIONS / encoded / session_id / "chat_history.jsonl"
        if cand.is_file():
            hist = cand
        else:
            for p in SESSIONS.glob(f"**/{session_id}/chat_history.jsonl"):
                hist = p
                break

    parsed = parse_history(hist, case["prompt"]) if hist.is_file() else parse_history(Path("/dev/null"), "")
    answer = parsed["answer"] or text
    expect_n = case["expect_notes"]
    rn = (not case["negative"]) and right_note(parsed["note_hits"], expect_n, answer)
    used = (not case["negative"]) and used_vault(answer, expect_n, case["expect_facts"])

    return {
        "id": case["id"],
        "prompt": case["prompt"],
        "hard": case["hard"],
        "negative": case["negative"],
        "tags": case["tags"],
        "expect_notes": expect_n,
        "session_id": session_id,
        "history": str(hist) if hist.is_file() else "",
        "rc": rc,
        "elapsed_s": round(time.time() - started, 1),
        "searched": parsed["searched"],
        "mcp": parsed["mcp"],
        "skill": parsed["skill"],
        "memory_search": parsed["memory_search"],
        "grep_vault": parsed["grep_vault"],
        "tools": parsed["tools"],
        "note_hits": parsed["note_hits"],
        "right_note": rn,
        "used": used,
        "answer_preview": answer[:1200],
        "setup_preview": setup_text[:400],
        "error": err[:800],
    }


# ── reporting ──────────────────────────────────────────────────────────────

def summarize(rows: list[dict]) -> dict:
    pos = [r for r in rows if not r["negative"] and r.get("rc") != 124]
    hard = [r for r in pos if r["hard"]]
    easy = [r for r in pos if not r["hard"]]
    neg = [r for r in rows if r["negative"] and r.get("rc") != 124]
    timed_out = [r for r in rows if r.get("rc") == 124]

    def rate(xs, key):
        if not xs:
            return None
        return round(100.0 * sum(1 for r in xs if r.get(key)) / len(xs), 1)

    fail_search = [r["prompt"] for r in pos if not r["searched"]]
    fail_note = [r["prompt"] for r in pos if r["searched"] and not r["right_note"]]
    fail_used = [r["prompt"] for r in pos if r["right_note"] and not r["used"]]
    hard_fail = [r["prompt"] for r in hard if not (r["searched"] and r["right_note"])]
    fp = [r["prompt"] for r in neg if r["searched"]]

    return {
        "n": len(rows),
        "n_pos": len(pos),
        "n_hard": len(hard),
        "n_easy": len(easy),
        "n_neg": len(neg),
        "n_timeout": len(timed_out),
        "recall_overall_search": rate(pos, "searched"),
        "recall_overall_note": rate(pos, "right_note"),
        "recall_overall_used": rate(pos, "used"),
        "recall_hard_search": rate(hard, "searched"),
        "recall_hard_note": rate(hard, "right_note"),
        "recall_hard_and": (
            round(100.0 * sum(1 for r in hard if r["searched"] and r["right_note"]) / len(hard), 1)
            if hard else None
        ),
        "recall_easy_search": rate(easy, "searched"),
        "false_positive_rate": rate(neg, "searched"),
        "failing_prompts_no_search": fail_search,
        "failing_prompts_wrong_note": fail_note,
        "failing_prompts_unused": fail_used,
        "hard_failing_prompts": hard_fail,
        "false_positive_prompts": fp,
        "timeout_ids": [r["id"] for r in timed_out],
    }


def print_report(rows: list[dict], title: str) -> None:
    s = summarize(rows)
    print(f"\n══ {title} ══")
    print(f"n={s['n']}  pos={s['n_pos']} (hard {s['n_hard']} / easy {s['n_easy']})  "
          f"neg={s['n_neg']}  timeout={s['n_timeout']}")
    print(f"recall overall  search={s['recall_overall_search']}%  "
          f"right_note={s['recall_overall_note']}%  used={s['recall_overall_used']}%")
    print(f"recall HARD     search={s['recall_hard_search']}%  "
          f"right_note={s['recall_hard_note']}%  "
          f"search∧note={s['recall_hard_and']}%   ← cancel criterion is this ≥90")
    print(f"recall easy     search={s['recall_easy_search']}%")
    print(f"false-positive  {s['false_positive_rate']}%  (searched on a negative control)")

    def dump(label, xs):
        print(f"\n{label} ({len(xs)}):")
        if not xs:
            print("  (none)")
            return
        for p in xs:
            print(f"  · {p}")

    dump("HARD failures (no search or wrong note) — VERBATIM", s["hard_failing_prompts"])
    dump("positives that never searched — VERBATIM", s["failing_prompts_no_search"])
    dump("searched but missed the right note — VERBATIM", s["failing_prompts_wrong_note"])
    dump("false-positive prompts — VERBATIM", s["false_positive_prompts"])
    if s["timeout_ids"]:
        print("timeouts:", ", ".join(s["timeout_ids"]))


def local_coverage(mod) -> list[dict]:
    rows = []
    for c in CASES:
        ctx = mod.retrieve(c["prompt"])
        got = notes_from_ctx(ctx)
        hit = bool(got) and (
            c["negative"] or any(stem_match(g, c["expect_notes"]) for g in got)
        )
        rows.append({
            "id": c["id"],
            "prompt": c["prompt"],
            "hard": c["hard"],
            "negative": c["negative"],
            "scorer_hit": bool(got),
            "scorer_right": hit if not c["negative"] else False,
            "scorer_notes": got,
            "scorer_fp": c["negative"] and bool(got),
        })
        flag = "FP  " if c["negative"] and got else (
            "HIT " if got else "MISS"
        )
        extra = f"  notes={[Path(n).name for n in got]}" if got else ""
        mark = " HARD" if c["hard"] else (" NEG" if c["negative"] else "")
        print(f"{flag}{mark:5}  {c['id']:28}  {c['prompt']}{extra}")
    pos = [r for r in rows if not r["negative"]]
    hard = [r for r in pos if r["hard"]]
    neg = [r for r in rows if r["negative"]]
    print("\nretrieve() coverage (scorer, not the model):")
    print(f"  positives that retrieve anything: "
          f"{sum(r['scorer_hit'] for r in pos)}/{len(pos)}")
    print(f"  positives that retrieve the RIGHT note: "
          f"{sum(r['scorer_right'] for r in pos)}/{len(pos)}")
    print(f"  HARD that retrieve the right note: "
          f"{sum(r['scorer_right'] for r in hard)}/{len(hard)}")
    print(f"  negative-control scorer FP: "
          f"{sum(r['scorer_fp'] for r in neg)}/{len(neg)}")
    miss_hard = [r["prompt"] for r in hard if not r["scorer_right"]]
    print("  HARD retrieve() misses (model must grep / still search):")
    for p in miss_hard:
        print(f"    · {p}")
    return rows


def save_run(run_dir: Path, rows: list[dict], extra: dict) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "n_cases": len(CASES),
        "summary": summarize(rows),
        **extra,
        "rows": rows,
    }
    (run_dir / "results.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )
    (run_dir / "summary.json").write_text(
        json.dumps(payload["summary"], indent=2) + "\n", encoding="utf-8"
    )


def select_cases(ids: list[str] | None, smoke: bool) -> list[dict]:
    if smoke:
        want = {"megabonk-crypto", "waybar-blank", "neg-math"}
        return [c for c in CASES if c["id"] in want]
    if ids:
        want = set(ids)
        found = [c for c in CASES if c["id"] in want]
        missing = want - {c["id"] for c in found}
        if missing:
            raise SystemExit(f"unknown case ids: {sorted(missing)}")
        return found
    return list(CASES)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--local", action="store_true",
                    help="only score retrieve() against the prompt set")
    ap.add_argument("--run", action="store_true",
                    help="fire live grok -p sessions")
    ap.add_argument("--smoke", action="store_true",
                    help="3 live sessions: easy / hard / negative")
    ap.add_argument("--report", nargs="?", const="latest",
                    help="print a saved run (path or 'latest')")
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--timeout", type=int, default=180,
                    help="seconds per grok -p (default 180)")
    ap.add_argument("--ids", default="",
                    help="comma-separated case ids")
    ap.add_argument("--tag", default="",
                    help="label this run (e.g. before / after)")
    args = ap.parse_args()

    ids = [x.strip() for x in args.ids.split(",") if x.strip()] or None

    if args.report:
        if args.report == "latest":
            runs = sorted(OUT_ROOT.glob("*/results.json"))
            if not runs:
                raise SystemExit("no saved runs")
            path = runs[-1]
        else:
            path = Path(args.report)
            if path.is_dir():
                path = path / "results.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        print_report(data["rows"], f"saved {path}")
        return 0

    print(f"cases: {len(CASES)}  "
          f"hard={sum(c['hard'] for c in CASES)}  "
          f"easy={sum(not c['hard'] and not c['negative'] for c in CASES)}  "
          f"neg={sum(c['negative'] for c in CASES)}")
    print(f"positives={sum(not c['negative'] for c in CASES)}")

    mod = load_retrieve()
    if args.local or not (args.run or args.smoke):
        local_coverage(mod)
        if not (args.run or args.smoke):
            return 0

    cases = select_cases(ids, args.smoke)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    tag = args.tag or ("smoke" if args.smoke else "run")
    run_dir = OUT_ROOT / f"{stamp}-{tag}"
    run_dir.mkdir(parents=True, exist_ok=True)
    print(f"run dir: {run_dir}")
    print(f"grok: {GROK_BIN}  cwd: {CWD}  jobs={args.jobs}  n={len(cases)}")

    refresh_context()
    rows: list[dict] = []
    # Follow-ups must not race their own setup; run them sequentially inside
    # run_one. Independent cases can overlap.
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        futs = {ex.submit(run_one, c, args.timeout): c for c in cases}
        for i, fut in enumerate(concurrent.futures.as_completed(futs), 1):
            row = fut.result()
            rows.append(row)
            mark = (
                "FP" if row["negative"] and row["searched"] else
                "OK" if row["negative"] and not row["searched"] else
                "HIT" if row["searched"] and row["right_note"] else
                "SRCH" if row["searched"] else
                "MISS"
            )
            print(f"[{i}/{len(cases)}] {mark:4}  {row['id']:28}  "
                  f"search={row['searched']} mcp={row['mcp']} skill={row['skill']}  "
                  f"note={row['right_note']} used={row['used']}  "
                  f"{row['elapsed_s']}s  {row['prompt']!r}",
                  flush=True)
            (run_dir / "partial.json").write_text(
                json.dumps(rows, indent=2) + "\n", encoding="utf-8"
            )

    rows.sort(key=lambda r: [c["id"] for c in CASES].index(r["id"])
              if r["id"] in {c["id"] for c in CASES} else 999)
    save_run(run_dir, rows, {"tag": tag, "jobs": args.jobs, "timeout": args.timeout})
    print_report(rows, f"{tag}  {run_dir}")
    print(f"\nsaved {run_dir / 'results.json'}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
