#!/usr/bin/env python3
"""brain-prune-phase — remove the bulk-generated notes from the vault.

Criterion, from inspection of the 2026 generation runs: every machine-written
note carries a `phase:` frontmatter key or a `#phaseNN` tag. Notes Brandon wrote
himself carry neither. That single marker separates 427 generated notes from
311 real ones.

Nothing is deleted. Notes move to ~/.local/share/brain-pruned/ with their vault
paths preserved, so any of them can be restored with one `mv`. A full tarball
snapshot is written first regardless.

    brain-prune-phase.py            # dry run — counts and a sample
    brain-prune-phase.py --apply    # snapshot, then move
"""
import os
import re
import shutil
import sys
import tarfile

HOME = os.path.expanduser("~")
VAULT = os.environ.get("BRAIN_VAULT", os.path.join(HOME, "Documents", "Brain"))
PRUNED = os.path.join(HOME, ".local", "share", "brain-pruned")
SNAP_DIR = os.path.join(HOME, ".local", "share", "brain-snapshots")
SKIP = set([".git", ".obsidian", ".stfolder", ".trash"])
PHASE = re.compile(r"^phase:|phase\d+", re.M)

apply_it = "--apply" in sys.argv


def walk_md():
    for dp, dn, fn in os.walk(VAULT):
        dn[:] = [d for d in dn if d not in SKIP]
        for f in fn:
            if f.endswith(".md"):
                yield os.path.join(dp, f)


def snapshot(tag):
    os.makedirs(SNAP_DIR, exist_ok=True)
    path = os.path.join(SNAP_DIR, "brain-%s.tar.gz" % tag)
    with tarfile.open(path, "w:gz") as t:
        for dp, dn, fn in os.walk(VAULT):
            dn[:] = [d for d in dn if d not in SKIP]
            for f in fn:
                p = os.path.join(dp, f)
                t.add(p, arcname=os.path.relpath(p, VAULT))
    print("snapshot -> %s (%.1f MB)" % (path, os.path.getsize(path) / 1e6))


def main():
    total = 0
    targets = []
    for p in walk_md():
        total += 1
        head = open(p, encoding="utf-8", errors="ignore").read(400)
        if PHASE.search(head):
            targets.append(p)

    print("%d phase-marked of %d notes" % (len(targets), total))
    if not apply_it:
        for p in sorted(targets)[:12]:
            print("  would move:", os.path.relpath(p, VAULT))
        print("  ... dry run. Pass --apply to snapshot and move.")
        return 0

    snapshot("preprune")
    for p in targets:
        dest = os.path.join(PRUNED, os.path.relpath(p, VAULT))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.move(p, dest)
    print("moved %d notes -> %s" % (len(targets), PRUNED))

    removed = 0
    for dp, dn, fn in os.walk(VAULT, topdown=False):
        if set(dp.split(os.sep)) & SKIP or dp == VAULT:
            continue
        try:
            if not os.listdir(dp):
                os.rmdir(dp)
                removed += 1
        except OSError:
            pass
    print("removed %d empty dirs" % removed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
