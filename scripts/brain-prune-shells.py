#!/usr/bin/env python3
"""brain-prune-shells — second prune pass, after brain-prune-phase.

Pruning the phase notes left behind their index pages: MOCs and hubs whose
entire body is a list of links into the set that was just removed. They are not
notes any more, they're 404 pages, and they are what the dead-link count is now
made of.

A note is a shell when most of its outbound links point at files that no longer
exist. Nothing is deleted — same destination as the first pass,
~/.local/share/brain-pruned/, so restoring is one mv.

    brain-prune-shells.py             # dry run: list them with their dead ratio
    brain-prune-shells.py --apply
"""
import os
import re
import shutil
import sys

HOME = os.path.expanduser("~")
VAULT = os.environ.get("BRAIN_VAULT", os.path.join(HOME, "Documents", "Brain"))
PRUNED = os.path.join(HOME, ".local", "share", "brain-pruned")
SKIP = set([".git", ".obsidian", ".stfolder", ".trash"])
LINK = re.compile(r"\[\[([^\]|#]+)")

# How much of a note has to be dangling before it counts as an index for
# content that's gone. 0.7 keeps real notes that merely cite a pruned one.
DEAD_RATIO = 0.7
MIN_LINKS = 3

# Entrypoints are never pruned even when they're mostly dangling — the front
# page of the vault gets rewritten, not deleted.
KEEP = set(["home.md", "index.md", "readme.md", "about me.md"])

apply_it = "--apply" in sys.argv


def walk():
    for dp, dn, fn in os.walk(VAULT):
        dn[:] = [d for d in dn if d not in SKIP]
        for f in fn:
            if f.endswith(".md"):
                yield os.path.join(dp, f)


def main():
    paths = list(walk())
    titles = set(os.path.splitext(os.path.basename(p))[0].lower() for p in paths)

    shells = []
    for p in paths:
        if os.path.basename(p).lower() in KEEP:
            continue
        text = open(p, encoding="utf-8", errors="ignore").read()
        links = [t.strip().lower() for t in LINK.findall(text)]
        links = [t for t in links if t]
        if len(links) < MIN_LINKS:
            continue
        dead = sum(1 for t in links if t not in titles)
        ratio = dead / len(links)
        if ratio >= DEAD_RATIO:
            shells.append((ratio, dead, len(links), p))

    shells.sort(reverse=True)
    print("%d shell notes of %d" % (len(shells), len(paths)))
    for ratio, dead, tot, p in shells:
        print("  %3d%%  %2d/%2d dead  %s" % (ratio * 100, dead, tot,
                                             os.path.relpath(p, VAULT)))
    if not apply_it:
        print("  ... dry run. Pass --apply to move them.")
        return 0

    for _, _, _, p in shells:
        dest = os.path.join(PRUNED, os.path.relpath(p, VAULT))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.move(p, dest)
    print("moved %d shells -> %s" % (len(shells), PRUNED))

    for dp, dn, fn in os.walk(VAULT, topdown=False):
        if set(dp.split(os.sep)) & SKIP or dp == VAULT:
            continue
        try:
            if not os.listdir(dp):
                os.rmdir(dp)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
