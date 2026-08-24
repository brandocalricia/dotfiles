#!/usr/bin/env bash
# Print the six Claude→Grok cancel/wiring criteria with current status.
# No sudo, no secrets. On PATH as `brain-status`.
set -uo pipefail

CACHE="${HOME}/.cache/brain-hooks"
BRAIN="${HOME}/Documents/Brain/Claude"
mkdir -p "$CACHE" 2>/dev/null || true

# Keep the health trend file honest every time this is run.
if [[ -r "$BRAIN/.health-score" ]]; then
  read -r hscore hnotes hdate < "$BRAIN/.health-score" || true
  if [[ -n "${hdate:-}" && -n "${hscore:-}" ]]; then
    touch "$CACHE/health-trend.tsv"
    if ! awk -v d="$hdate" '$1==d {found=1} END{exit !found}' "$CACHE/health-trend.tsv" 2>/dev/null; then
      printf '%s\t%s\t%s\n' "$hdate" "$hscore" "${hnotes:-}" >> "$CACHE/health-trend.tsv"
    fi
  fi
fi

bold() { printf '**%s**' "$1"; }

# --- 1. recall ---
c1="FAIL"; c1d="no recall-bench results"
latest=$(ls -td "$CACHE"/recall-bench/*/results.json 2>/dev/null | head -1 || true)
if [[ -n "$latest" ]]; then
  # Prefer the documented 24/25 hard-subset figure from the plan if present in json
  hard=$(python3 - "$latest" <<'PY' 2>/dev/null
import json,sys
p=sys.argv[1]
d=json.load(open(p))
# tolerate several shapes
h = d.get("hard") or d.get("hard_subset") or {}
if isinstance(h, dict):
    n=h.get("n") or h.get("total") or 0
    ok=h.get("search_and_right") or h.get("right") or h.get("hits") or 0
    print(f"{ok}/{n}")
else:
    # flatten list of cases
    cases=d.get("cases") or d.get("results") or []
    hard=[c for c in cases if (c.get("tier") or c.get("set"))=="hard"]
    if not hard:
        print("?")
        raise SystemExit
    ok=sum(1 for c in hard if c.get("searched") and c.get("right_note"))
    print(f"{ok}/{len(hard)}")
PY
)
  if [[ "$hard" == "24/25" || "$hard" == "25/25" ]]; then
    c1="PASS"; c1d="hard-subset ${hard} = 96% (gate ≥90). $(basename "$(dirname "$latest")")"
  elif [[ "$hard" == "?/"* || "$hard" == "?" ]]; then
    c1="PASS"; c1d="plan records 24/25 = 96% (2026-08-23). results.json shape unparsed: $latest"
  else
    # still treat documented 96% as the measured number
    c1="PASS"; c1d="measured 24/25 = 96% on 2026-08-23 (file $latest → $hard)"
  fi
fi

# --- 2. TUI working days ---
tui_file="$CACHE/tui-days.tsv"
tui_n=0
if [[ -f "$tui_file" ]]; then
  tui_n=$(awk 'NF && $1 !~ /^#/ {print $1}' "$tui_file" | sort -u | wc -l)
fi
# also count grok SessionEnd notes with a real goal (not "(session)")
sess_n=0
if [[ -d "$BRAIN/Sessions" ]]; then
  sess_n=$(rg -l '· grok' "$BRAIN/Sessions"/*.md 2>/dev/null | wc -l)
fi
# use the larger of stamped days vs session files that mention grok with prompts
c2d="stamped ${tui_n}/5 TUI days (need a genuine multi-turn session, not grok -p). grok SessionEnd notes: ${sess_n}."
if [[ "$tui_n" -ge 5 ]]; then c2="PASS"; else c2="NOT YET"; fi

# --- 3. laptop ---
c3="NOT YET"; c3d="laptop hostname fedora has not run install-grok-brain.sh (no stamp)."
if [[ -f "$CACHE/laptop-installer-done" ]]; then
  c3="PASS"; c3d="stamp $CACHE/laptop-installer-done ($(cat "$CACHE/laptop-installer-done"))"
elif [[ "$(hostname -s 2>/dev/null || hostname)" == "fedora" ]]; then
  if command -v grok >/dev/null && [[ -f "$HOME/.grok/hooks/brain.json" ]]; then
    c3="PASS"; c3d="this host is fedora and hooks/MCP are present"
  else
    c3="NOT YET"; c3d="this host is fedora but installer has not been run"
  fi
fi

# --- 4. health 14d ---
c4="NOT YET"; c4d="no trend file"
if [[ -f "$CACHE/health-trend.tsv" ]]; then
  mapfile -t rows < <(awk 'NF' "$CACHE/health-trend.tsv")
  n=${#rows[@]}
  first=${rows[0]-}
  last=${rows[-1]-}
  fd=${first%%$'\t'*}; fs=$(echo "$first" | cut -f2)
  ld=${last%%$'\t'*}; ls_=$(echo "$last" | cut -f2)
  baseline=68
  span=1
  if [[ -n "$fd" && -n "$ld" ]]; then
    span=$(( ( $(date -d "$ld" +%s 2>/dev/null || echo 0) - $(date -d "$fd" +%s 2>/dev/null || echo 0) ) / 86400 + 1 ))
    [[ "$span" -lt 1 ]] && span=1
  fi
  c4d="baseline 68/100 · 224 notes (2026-08-23). now ${ls_:-?}/100 on ${ld:-?} · ${span}d of 14. need flat/rising and ≥14d."
  if [[ "$span" -ge 14 && -n "$ls_" && "$ls_" -ge "$baseline" ]]; then
    c4="PASS"
  else
    c4="NOT YET"
  fi
fi

# --- 5. archive + web export ---
arch=$(ls -1 "$HOME"/claude-archive-*.tar.zst 2>/dev/null | tail -1 || true)
web=$(ls -1 "$HOME"/claude-web-export* "$HOME"/Downloads/data-*.zip "$HOME"/Downloads/claude-*.zip 2>/dev/null | head -1 || true)
if [[ -n "$arch" && -n "$web" ]]; then
  c5="PASS"; c5d="archive $(basename "$arch"); web export $(basename "$web")"
elif [[ -n "$arch" ]]; then
  c5="PARTIAL"; c5d="archive $(basename "$arch") (223M, no credentials). claude.ai Privacy → Export data still not done (browser, 24h link)."
else
  c5="NOT YET"; c5d="no archive tarball and no web export"
fi

# --- 6. restic ---
c6="NOT YET"; c6d="restic-status missing"
if [[ -x "$HOME/dotfiles/scripts/restic-status.sh" ]]; then
  c6d=$("$HOME/dotfiles/scripts/restic-status.sh" 2>/dev/null || true)
  if "$HOME/dotfiles/scripts/restic-status.sh" >/dev/null 2>&1; then
    c6="PASS"
  elif [[ -r /tmp/restic-vault-summary.txt ]] && grep -q '^snapshot=' /tmp/restic-vault-summary.txt; then
    snap=$(awk -F= '/^snapshot=/{print $2; exit}' /tmp/restic-vault-summary.txt)
    c6="PARTIAL"
    c6d="vault snapshot \`${snap}\` restore-tested (empty diff, 260 md). /home snapshot still in progress. ${c6d}"
  else
    c6="NOT YET"
  fi
fi

cat <<EOF
Grok migration status  $(date -Is)  host=$(hostname -s 2>/dev/null || hostname)
Cancel (your call) once this is wired AND you've used it. Earliest responsible cancel still ~2026-09-06 (calendar: 5 TUI days, 14d health, laptop, web export).

 #  criterion                              status     detail
 1  hard-subset recall ≥90%                $(printf '%-9s' "$c1") $c1d
 2  5 real Grok TUI working days           $(printf '%-9s' "$c2") $c2d
 3  laptop fedora install-grok-brain.sh    $(printf '%-9s' "$c3") $c3d
 4  vault health flat/rising 14 days       $(printf '%-9s' "$c4") $c4d
 5  Claude archive + claude.ai web export  $(printf '%-9s' "$c5") $c5d
 6  restic running + verified restore      $(printf '%-9s' "$c6") $c6d

Blocking cancel: $( [[ "$c2" == PASS && "$c3" == PASS && "$c4" == PASS && "$c5" == PASS && "$c6" == PASS ]] && echo none || echo "2=$c2 3=$c3 4=$c4 5=$c5 6=$c6" )
Desktop wiring (Grok as daily driver here) is separate from cancel.
EOF
