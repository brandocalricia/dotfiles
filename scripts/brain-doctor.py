#!/usr/bin/env python3
"""
brain-doctor — audit and repair the Obsidian vault at ~/Documents/Brain.

Modes (composable):
  --audit           analyse only, write Claude/Health.md + print score   [default]
  --fix             apply mechanical, non-destructive repairs
  --unlink          convert fabricated [[links]] to plain text
  --archive         move non-note clutter out of the vault
  --all             --fix --unlink --archive, then re-audit
  --dry-run         report what each mode would do, change nothing

Everything here is idempotent: running it twice is a no-op the second time.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from collections import Counter, defaultdict
from datetime import date, datetime
from pathlib import Path

import yaml

VAULT = Path(os.environ.get("BRAIN_VAULT", Path.home() / "Documents" / "Brain"))
ARCHIVE = Path(os.environ.get("BRAIN_ARCHIVE", Path.home() / "Documents" / "Brain-archive"))
REPORT = VAULT / "Claude" / "Health.md"
SCORE_CACHE = VAULT / "Claude" / ".health-score"

SKIP_DIRS = {".git", ".obsidian", ".stfolder", ".trash", "node_modules"}
# Folders whose contents are transcripts/exports, not notes. Archived, not deleted.
CLUTTER_DIRS = ["copilot"]
# Directories that must survive being empty (Obsidian/workflow entry points).
KEEP_EMPTY = {"00-Inbox", "attachments", "05-Templates"}

# A broken link target matching any of these was manufactured by a previous
# bulk-generation pass and will never become a real note.
SCAFFOLD_PATTERNS = [
    re.compile(p, re.I)
    for p in (
        r"\bphase\s*-?\d+\b",
        r"\b\d+(st|nd|rd|th)[- ]order\b",
        r"^(first|second|third|fourth|fifth|sixth|seventh)[- ]order\b",
        r"^meta-move-",
        r"^cluster-",
        r"^boost-",
        r"^_post-metrics",
        r"^moc\s*[-—–]\s*(synthesis|meta-synthesis|.*\border\b.*questions)",
        r"^(audit|traversability|density|usage)[- ]",
        r"^(index-update|metrics)$",
        r"\.(css|json|sh|py)$",
        # prose about linking that got bracketed by mistake, never a real note
        r"^(links?|wikilinks?|notes?|tags?|folder|example)$",
    )
]


def is_scaffold_target(name: str) -> bool:
    """Assertion-shaped titles ('Markets or States for Legibility') are generated.

    Hand-written note titles are noun phrases; five-plus words means the
    generator emitted a claim as a filename. Four words stays out of this —
    that bucket holds real book titles (Skin in the Game).
    """
    if any(rx.search(name) for rx in SCAFFOLD_PATTERNS):
        return True
    return len(name.split()) >= 5 and not name.lower().startswith("moc")

LINK_RE = re.compile(r"\[\[([^\]]+?)\]\]", re.S)


# --------------------------------------------------------------------------
# vault model
# --------------------------------------------------------------------------
def walk_notes(root: Path) -> list[Path]:
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if fn.endswith(".md"):
                out.append(Path(dirpath) / fn)
    return sorted(out)


def norm(stem: str) -> str:
    """Collapse MOC prefixes/suffixes and punctuation so name variants match."""
    s = re.sub(r"\s+", " ", stem.strip())
    s = re.sub(r"^MOC\s*[-—–]\s*", "", s, flags=re.I)
    s = re.sub(r"\s*MOC$", "", s, flags=re.I)
    return re.sub(r"[^a-z0-9]", "", s.lower())


def split_frontmatter(text: str) -> tuple[dict | None, str, str]:
    """Return (parsed_frontmatter, raw_frontmatter_block, body)."""
    if not text.startswith("---"):
        return None, "", text
    end = text.find("\n---", 3)
    if end == -1:
        return None, "", text
    raw = text[: end + 4]
    body = text[end + 4 :]
    try:
        data = yaml.safe_load(text[3:end]) or {}
        if not isinstance(data, dict):
            data = {}
    except yaml.YAMLError:
        data = {}
    return data, raw, body


def link_targets(text: str) -> list[str]:
    """Wikilink targets, with embedded newlines collapsed and anchors stripped."""
    out = []
    for raw in LINK_RE.findall(text):
        t = re.sub(r"\s+", " ", raw.split("|")[0].split("#")[0]).strip()
        if t:
            out.append(t)
    return out


class Vault:
    def __init__(self, root: Path):
        self.root = root
        self.notes = walk_notes(root)
        self.text: dict[Path, str] = {}
        self.fm: dict[Path, dict] = {}
        self.by_stem: dict[str, list[Path]] = defaultdict(list)
        self.by_norm: dict[str, list[Path]] = defaultdict(list)

        for p in self.notes:
            try:
                t = p.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            self.text[p] = t
            data, _, _ = split_frontmatter(t)
            self.fm[p] = data or {}
            stem = p.stem
            self.by_stem[stem].append(p)
            self.by_norm[norm(stem)].append(p)
            for a in self._aliases(data or {}):
                self.by_stem[a].append(p)
                self.by_norm[norm(a)].append(p)

    @staticmethod
    def _aliases(fm: dict) -> list[str]:
        a = fm.get("aliases") or fm.get("alias") or []
        if isinstance(a, str):
            a = [a]
        return [str(x) for x in a if x]

    def is_scaffold_note(self, p: Path) -> bool:
        """Notes produced by the bulk-generation passes."""
        fm = self.fm.get(p, {})
        if "phase" in fm:
            return True
        tags = fm.get("tags") or []
        if isinstance(tags, str):
            tags = [tags]
        if any(re.search(r"phase-?\d", str(t), re.I) for t in tags):
            return True
        rel = p.relative_to(self.root).as_posix()
        return bool(re.search(r"/[2-5]\d-[A-Z]", "/" + rel))

    # ---- analysis -------------------------------------------------------
    def analyse(self) -> dict:
        inbound = Counter()
        outbound = Counter()
        broken = Counter()
        broken_sources: dict[str, set[Path]] = defaultdict(set)
        aliasable: dict[str, list[Path]] = {}
        multiline: list[Path] = []
        no_fm: list[Path] = []
        stubs: list[Path] = []

        for p in self.notes:
            t = self.text.get(p, "")
            if not t.startswith("---"):
                no_fm.append(p)
            if len(t.strip()) < 200:
                stubs.append(p)
            if any("\n" in m for m in LINK_RE.findall(t)):
                multiline.append(p)

            targets = link_targets(t)
            outbound[p] = len(targets)
            for tgt in targets:
                base = os.path.basename(tgt)
                hit = self.by_stem.get(base) or self.by_stem.get(tgt)
                if hit:
                    inbound[hit[0]] += 1
                    continue
                broken[base] += 1
                broken_sources[base].add(p)
                near = self.by_norm.get(norm(base))
                if near:
                    aliasable[base] = near

        fabricated, plausible = Counter(), Counter()
        for tgt, n in broken.items():
            if tgt in aliasable:
                continue
            srcs = broken_sources[tgt]
            only_scaffold_srcs = bool(srcs) and all(self.is_scaffold_note(s) for s in srcs)
            (fabricated if (is_scaffold_target(tgt) or only_scaffold_srcs) else plausible)[tgt] = n

        orphans = [
            p for p in self.notes
            if inbound[p] == 0 and not self._is_entrypoint(p)
        ]
        isolated = [p for p in orphans if outbound[p] == 0]
        dups = {k: v for k, v in self.by_stem.items() if len(set(v)) > 1 and k in {p.stem for p in v}}
        empty_dirs = [
            d for d in self._empty_dirs()
            if d.name not in KEEP_EMPTY
        ]
        clutter = [VAULT / c for c in CLUTTER_DIRS if (VAULT / c).is_dir()]

        return {
            "notes": len(self.notes),
            "inbound": inbound,
            "broken_total": sum(broken.values()),
            "aliasable": aliasable,
            "aliasable_count": sum(broken[t] for t in aliasable),
            "fabricated": fabricated,
            "plausible": plausible,
            "multiline": multiline,
            "no_frontmatter": no_fm,
            "stubs": stubs,
            "orphans": orphans,
            "isolated": isolated,
            "duplicates": dups,
            "empty_dirs": empty_dirs,
            "clutter": clutter,
        }

    def _empty_dirs(self) -> list[Path]:
        """Directories holding no files at any depth."""
        out = []
        for dirpath, dirnames, filenames in os.walk(self.root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            d = Path(dirpath)
            if d == self.root:
                continue
            if not any(f for f in filenames if not f.startswith(".")) and not dirnames:
                out.append(d)
        return out

    def _is_entrypoint(self, p: Path) -> bool:
        rel = p.relative_to(self.root).as_posix()
        return (
            rel.startswith(("Claude/Sessions/", "Claude/Rollups/", "06-Journal/", "05-Templates/"))
            or p.stem in {"INDEX", "Brain MOC", "Health"}
        )


def score(a: dict) -> tuple[int, list[str]]:
    """0-100 health score plus the deductions that produced it."""
    n = max(a["notes"], 1)
    deductions = []

    def hit(label: str, raw: float, cap: int):
        pts = min(cap, round(raw))
        if pts:
            deductions.append(f"-{pts} {label}")
        return pts

    total = 100
    total -= hit("dead links", (len(a["fabricated"]) + len(a["plausible"])) / n * 60, 35)
    total -= hit("orphans", len(a["orphans"]) / n * 60, 20)
    total -= hit("isolated notes", len(a["isolated"]) / n * 80, 15)
    total -= hit("unresolved aliases", len(a["aliasable"]) * 0.3, 10)
    total -= hit("missing frontmatter", len(a["no_frontmatter"]) * 0.3, 8)
    total -= hit("duplicate titles", len(a["duplicates"]) * 0.8, 7)
    total -= hit("clutter/empty dirs", (len(a["empty_dirs"]) + len(a["clutter"]) * 4) * 0.8, 5)
    return max(0, total), deductions


# --------------------------------------------------------------------------
# repairs
# --------------------------------------------------------------------------
def fix_multiline_links(v: Vault, a: dict, dry: bool) -> int:
    changed = 0
    for p in a["multiline"]:
        t = v.text[p]
        new = LINK_RE.sub(lambda m: "[[" + re.sub(r"\s+", " ", m.group(1)).strip() + "]]", t)
        if new != t:
            changed += 1
            if not dry:
                p.write_text(new, encoding="utf-8")
                v.text[p] = new
    return changed


def add_aliases(v: Vault, a: dict, dry: bool) -> int:
    """Give each rename-victim note an alias so existing links resolve."""
    wanted: dict[Path, set[str]] = defaultdict(set)
    for missing, candidates in a["aliasable"].items():
        wanted[candidates[0]].add(missing)

    changed = 0
    for p, names in wanted.items():
        t = v.text[p]
        fm, raw, body = split_frontmatter(t)
        fm = dict(fm or {})
        have = set(Vault._aliases(fm))
        add = {n for n in names if n not in have and n != p.stem}
        if not add:
            continue
        fm["aliases"] = sorted(have | add)
        new = "---\n" + yaml.safe_dump(fm, allow_unicode=True, sort_keys=False) + "---" + (body if raw else "\n\n" + t)
        changed += 1
        if not dry:
            p.write_text(new, encoding="utf-8")
            v.text[p] = new
    return changed


def add_frontmatter(v: Vault, a: dict, dry: bool) -> int:
    changed = 0
    for p in a["no_frontmatter"]:
        t = v.text[p]
        created = datetime.fromtimestamp(p.stat().st_mtime).date().isoformat()
        fm = {"title": p.stem, "created": created, "tags": []}
        new = "---\n" + yaml.safe_dump(fm, allow_unicode=True, sort_keys=False) + "---\n\n" + t.lstrip()
        changed += 1
        if not dry:
            p.write_text(new, encoding="utf-8")
            v.text[p] = new
    return changed


def unlink_fabricated(v: Vault, a: dict, dry: bool) -> tuple[int, int]:
    """[[Fabricated Target]] -> Fabricated Target (plain text). Files, occurrences."""
    dead = set(a["fabricated"])
    if not dead:
        return 0, 0
    files = occ = 0

    def repl(m):
        nonlocal occ
        raw = m.group(1)
        tgt = re.sub(r"\s+", " ", raw.split("|")[0].split("#")[0]).strip()
        if os.path.basename(tgt) in dead:
            occ += 1
            return raw.split("|")[-1].strip() if "|" in raw else tgt
        return m.group(0)

    for p in v.notes:
        t = v.text.get(p, "")
        before = occ
        new = LINK_RE.sub(repl, t)
        if occ != before and new != t:
            files += 1
            if not dry:
                p.write_text(new, encoding="utf-8")
                v.text[p] = new
    return files, occ


# Same stem, but genuinely different notes — never treat these as duplicates.
DEDUPE_EXEMPT = {
    "INDEX",            # Claude/INDEX.md (brain) vs 02-Notes/INDEX.md (vault)
    "Template-Weekly-Review",  # Automation/ and Journal/ variants are both used
    "Brando-Extensions",       # 01-Projects + 04-Archive is the intended pattern
    "DevPilot",
}


def snapshot() -> Path | None:
    """Tar the vault before anything irreversible. The vault is not a git repo
    (a .git dir inside a Syncthing share corrupts under concurrent sync), so this
    is the only local undo that exists. Keeps the 10 most recent.
    """
    snap_dir = Path.home() / ".local" / "share" / "brain-snapshots"
    snap_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y-%m-%dT%H%M%S")
    dest = snap_dir / f"brain-{stamp}.tar.gz"
    import subprocess
    r = subprocess.run(
        ["tar", "czf", str(dest), "-C", str(VAULT.parent), VAULT.name],
        capture_output=True,
    )
    if r.returncode != 0:
        return None
    old = sorted(snap_dir.glob("brain-*.tar.gz"))[:-10]
    for f in old:
        f.unlink(missing_ok=True)
    return dest


def dedupe(v: Vault, a: dict, dry: bool) -> list[str]:
    """Archive the unreferenced copy of a colliding title. Nothing is deleted.

    Obsidian resolves [[Stem]] to one arbitrary file when several share a stem,
    so collisions silently misroute links. The copy with inbound links is the one
    the vault actually uses; the other goes to 04-Archive/duplicates/.
    """
    dest_dir = VAULT / "04-Archive" / "duplicates"
    moved = []
    for stem, paths in sorted(a["duplicates"].items()):
        if stem in DEDUPE_EXEMPT:
            continue
        uniq = sorted(set(paths))
        # Rank by: most inbound links, then filed in a real folder over dumped at
        # the vault root, then longest.
        ranked = sorted(
            uniq,
            key=lambda p: (-a["inbound"][p], p.parent == VAULT, -len(v.text.get(p, ""))),
        )
        keep, losers = ranked[0], ranked[1:]
        # Nothing references any copy: only safe to act if the loser is a root-level
        # stray and the keeper is properly filed. Otherwise a human should look.
        if a["inbound"][keep] == 0 and stem != "_post-metrics":
            if not (keep.parent != VAULT and all(p.parent == VAULT for p in losers)):
                continue
        for p in losers:
            if a["inbound"][p] > 0:
                continue  # both referenced — needs a human merge, leave it
            rel = p.relative_to(VAULT)
            target = dest_dir / f"{p.parent.name}--{p.name}"
            moved.append(f"{rel} -> 04-Archive/duplicates/{target.name} (kept {keep.relative_to(VAULT)})")
            if not dry:
                dest_dir.mkdir(parents=True, exist_ok=True)
                shutil.move(str(p), str(target))
    return moved


def archive_clutter(a: dict, dry: bool) -> list[str]:
    moved = []
    for src in a["clutter"]:
        dest = ARCHIVE / src.name
        moved.append(f"{src.relative_to(VAULT)} -> {dest}")
        if not dry:
            ARCHIVE.mkdir(parents=True, exist_ok=True)
            if dest.exists():
                dest = ARCHIVE / f"{src.name}-{date.today().isoformat()}"
            shutil.move(str(src), str(dest))
    for d in a["empty_dirs"]:
        moved.append(f"rmdir {d.relative_to(VAULT)}")
        if not dry:
            try:
                d.rmdir()
            except OSError:
                pass
    return moved


# --------------------------------------------------------------------------
# report
# --------------------------------------------------------------------------
def write_report(a: dict, sc: int, deductions: list[str], actions: list[str]) -> None:
    def rels(paths, n=12):
        return [str(p.relative_to(VAULT)) for p in list(paths)[:n]]

    bar = "█" * (sc // 5) + "░" * (20 - sc // 5)
    L = [
        "---",
        "tags: [claude, health, generated]",
        f"updated: {date.today().isoformat()}",
        f"score: {sc}",
        "---",
        "# Vault Health",
        "",
        f"**{sc}/100**  `{bar}`  ·  {a['notes']} notes  ·  {date.today().isoformat()}",
        "",
        "> Generated by `brain-doctor.py`. Do not hand-edit — it is overwritten.",
        "",
    ]
    if deductions:
        L += ["Deductions: " + ", ".join(deductions), ""]
    if actions:
        L += ["## Last run applied", ""] + [f"- {x}" for x in actions] + [""]

    L += [
        "## Metrics",
        "",
        "| Check | Count |",
        "|---|---|",
        f"| Broken link occurrences | {a['broken_total']} |",
        f"| → resolvable via alias | {a['aliasable_count']} ({len(a['aliasable'])} targets) |",
        f"| → fabricated (unlinkable) | {sum(a['fabricated'].values())} ({len(a['fabricated'])} targets) |",
        f"| → plausible, to write | {sum(a['plausible'].values())} ({len(a['plausible'])} targets) |",
        f"| Orphans (no inbound) | {len(a['orphans'])} |",
        f"| Fully isolated | {len(a['isolated'])} |",
        f"| Missing frontmatter | {len(a['no_frontmatter'])} |",
        f"| Duplicate titles | {len(a['duplicates'])} |",
        f"| Stub notes (<200 chars) | {len(a['stubs'])} |",
        f"| Empty dirs | {len(a['empty_dirs'])} |",
        "",
    ]

    if a["plausible"]:
        L += [
            "## Write queue",
            "",
            "Real concepts you linked to but never wrote — highest leverage first.",
            "",
        ]
        L += [f"- **{t}** — referenced {n}×" for t, n in a["plausible"].most_common(25)]
        L.append("")

    if a["duplicates"]:
        L += ["## Duplicate titles", ""]
        for k, v in list(a["duplicates"].items())[:15]:
            L.append(f"- `{k}` — " + ", ".join(f"`{p.relative_to(VAULT)}`" for p in sorted(set(v))))
        L.append("")

    if a["isolated"]:
        L += ["## Isolated notes", "", "No links in or out — invisible to the graph and to retrieval.", ""]
        L += [f"- `{r}`" for r in rels(a["isolated"], 20)]
        if len(a["isolated"]) > 20:
            L.append(f"- …and {len(a['isolated']) - 20} more")
        L.append("")

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text("\n".join(L), encoding="utf-8")
    SCORE_CACHE.write_text(f"{sc} {a['notes']} {date.today().isoformat()}\n", encoding="utf-8")


# --------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description="Audit and repair the Obsidian vault.")
    ap.add_argument("--audit", action="store_true")
    ap.add_argument("--fix", action="store_true")
    ap.add_argument("--unlink", action="store_true")
    ap.add_argument("--archive", action="store_true")
    ap.add_argument("--dedupe", action="store_true", help="archive unreferenced duplicate-title notes")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--quiet", action="store_true", help="print only the score line")
    args = ap.parse_args()

    if args.all:
        args.fix = args.unlink = args.archive = args.dedupe = True
    if not any((args.fix, args.unlink, args.archive, args.dedupe)):
        args.audit = True

    if not VAULT.is_dir():
        print(f"brain-doctor: vault not found at {VAULT}", file=sys.stderr)
        return 1

    dry = args.dry_run
    actions: list[str] = []

    # Anything that moves or rewrites files gets a restore point first.
    if not dry and (args.fix or args.unlink or args.archive or args.dedupe):
        snap = snapshot()
        if snap:
            actions.append(f"snapshot → `{snap}`")

    v = Vault(VAULT)
    a = v.analyse()

    if args.archive or args.dedupe:
        moved = []
        if args.dedupe:
            moved += dedupe(v, a, dry)
        if args.archive:
            moved += archive_clutter(a, dry)
        for line in moved:
            actions.append(f"archived/removed `{line}`")
        if moved and not dry:
            # paths just moved off disk; re-scan before any edit pass
            v = Vault(VAULT)
            a = v.analyse()
    if args.fix:
        n = fix_multiline_links(v, a, dry)
        if n:
            actions.append(f"collapsed wrapped wikilinks in {n} notes")
        n = add_aliases(v, a, dry)
        if n:
            actions.append(f"added aliases to {n} notes ({a['aliasable_count']} links now resolve)")
        n = add_frontmatter(v, a, dry)
        if n:
            actions.append(f"added frontmatter to {n} notes")
    if args.unlink:
        files, occ = unlink_fabricated(v, a, dry)
        if occ:
            actions.append(f"unlinked {occ} fabricated links across {files} notes")

    if actions and not dry:
        v = Vault(VAULT)
        a = v.analyse()

    sc, deductions = score(a)
    if not dry:
        write_report(a, sc, deductions, actions)

    if args.quiet:
        print(f"{sc} {a['notes']}")
        return 0

    tag = "[dry-run] " if dry else ""
    print(f"{tag}vault health: {sc}/100 · {a['notes']} notes")
    print(f"  broken links      {a['broken_total']}  "
          f"(alias-fixable {a['aliasable_count']} / fabricated {sum(a['fabricated'].values())} "
          f"/ to-write {sum(a['plausible'].values())})")
    print(f"  orphans           {len(a['orphans'])}  (isolated {len(a['isolated'])})")
    print(f"  no frontmatter    {len(a['no_frontmatter'])}")
    print(f"  duplicate titles  {len(a['duplicates'])}")
    for x in actions:
        print(f"  ✓ {x}")
    if not dry:
        print(f"  report → {REPORT.relative_to(Path.home())}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
