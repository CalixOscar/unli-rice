#!/bin/sh
# lint-project-notes.sh — structural check for PROJECT_NOTES.md
#
# Exists because a note can be corrupted by any tool that edits it, and the studio
# swaps between several. Vault guardrails only bind tools that read them; this runs
# from a git pre-commit hook, so it binds every tool equally.
#
# Usage:
#   scripts/lint-project-notes.sh [path]            check the whole file
#   scripts/lint-project-notes.sh --staged [path]   content rules apply only to
#                                                   newly added lines (hook mode)
#
# Two deliberate design choices, both learned the hard way on 2026-08-29:
#   * Content rules (evidence for test claims) run against ADDED lines only. The
#     logs are append-only historical record; demanding evidence retroactively
#     would force exactly the rewriting of old entries the guardrails forbid.
#   * A known, deliberately-deferred structural issue can be waived in-file with
#     a lint-allow marker. A linter that blocks on a deferral you already decided
#     on just trains you to pass --no-verify, which costs you every other check.
#
# Exit 1 on error, 0 otherwise. Warnings never block.

STAGED=0
if [ "$1" = "--staged" ]; then STAGED=1; shift; fi
F="${1:-PROJECT_NOTES.md}"
SIZE_WARN="${NOTES_SIZE_WARN:-40000}"
ERR=0

fail() { printf '  ERROR  %s\n' "$1"; ERR=1; }
warn() { printf '  warn   %s\n' "$1"; }

[ -f "$F" ] || { printf 'lint-project-notes: no such file: %s\n' "$F"; exit 1; }
printf 'lint-project-notes: %s%s\n' "$F" "$([ "$STAGED" -eq 1 ] && echo ' (staged mode)')"

# Waivers: <!-- lint-allow duplicate-heading "## Session Log" — reason, date -->
allowed() { grep -qF "lint-allow $1 \"$2\"" "$F"; }

# --- 1. filename must not shadow a vault _AI Context/ file -------------------
case "$(basename "$F")" in
  0[0-9]_*) fail "filename shadows the vault's _AI Context/ numbering — name project notes after the project" ;;
esac

# --- 2. no duplicate '## ' headings (waivable) -------------------------------
grep '^## ' "$F" | sort | uniq -d | while IFS= read -r d; do
  [ -n "$d" ] || continue
  ESC=$(printf '%s' "$d" | sed 's/[][\.*^$/]/\\&/g')
  LINES=$(grep -n "^$ESC$" "$F" | cut -d: -f1 | tr '\n' ' ')
  if allowed duplicate-heading "$d"; then
    printf '  waived duplicate section heading "%s" (lines: %s)\n' "$d" "$LINES"
  else
    printf '  ERROR  duplicate section heading "%s" at lines: %s\n' "$d" "$LINES"
    echo x >> "$F.lint-err"
  fi
done
[ -f "$F.lint-err" ] && { ERR=1; rm -f "$F.lint-err"; }

# --- 3. required sections present ---------------------------------------------
for S in "## Overview" "## Handoff" "## Decisions Log" "## Session Log"; do
  N=$(grep -c "^$S" "$F")
  if [ "$N" -eq 0 ]; then
    fail "missing required section '$S'"
  elif [ "$N" -gt 1 ] && ! allowed duplicate-heading "$S"; then
    : # already reported above
  fi
done

# --- 4. Handoff: six fields, in order, no sub-headings inside -----------------
HSTART=$(grep -n '^## Handoff' "$F" | head -1 | cut -d: -f1)
if [ -n "$HSTART" ]; then
  HEND=$(awk -v s="$HSTART" 'NR>s && /^## /{print NR; exit}' "$F")
  [ -n "$HEND" ] || HEND=$(( $(wc -l < "$F") + 1 ))

  INNER=$(awk -v s="$HSTART" -v e="$HEND" 'NR>s && NR<e && /^### /{c++} END{print c+0}' "$F")
  [ "$INNER" -eq 0 ] || fail "Handoff contains $INNER sub-heading(s) between lines $HSTART and $HEND — a field was split around inserted content"

  GOT=$(awk -v s="$HSTART" -v e="$HEND" 'NR>s && NR<e && /^\*\*[A-Z][A-Za-z ]*:\*\*/ {
          match($0, /^\*\*[^:]*:/); print substr($0, 3, RLENGTH-3) }' "$F" | tr '\n' ',')
  NORM=$(printf '%s' "$GOT" | sed 's/Files touched[^,]*/Files touched/')
  WANT="Status,Task,Files touched,Next step,Gotchas,Left by,"
  [ "$NORM" = "$WANT" ] || fail "Handoff fields wrong or out of order.
           expected: $WANT
           found:    $NORM"
fi

# --- 5. Left by must not be older than the newest dated entry -----------------
# Scoped to the Handoff section: the contract header names the fields too, and a
# bare grep would read the header's mention instead of the real field.
LEFTBY=$(awk -v s="${HSTART:-0}" -v e="${HEND:-0}" \
           'NR>s && NR<e && /^\*\*Left by:\*\*/{print; exit}' "$F" \
         | grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' | head -1)
NEWEST=$(grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$F" | sort | tail -1)
if [ -z "$LEFTBY" ]; then
  fail "**Left by:** carries no YYYY-MM-DD date"
elif [ -n "$NEWEST" ] && [ "$LEFTBY" \< "$NEWEST" ]; then
  warn "**Left by:** is $LEFTBY but the newest dated entry is $NEWEST — stale Handoff?"
fi

# --- 6. build/test claims must carry their evidence --------------------------
# Added lines only in staged mode: the logs are append-only history.
CLAIM_RE='[0-9]+ tests? (green|passing|pass\b)'
if [ "$STAGED" -eq 1 ]; then
  BAD=$(git diff --cached -U0 -- "$F" | grep '^+' | grep -v '^+++' | sed 's/^+//' \
        | grep -Ei "$CLAIM_RE" | grep -viE '\((verified|unverified)|unverified')
  [ -n "$BAD" ] && fail "new test-count claim without evidence:
           $(printf '%s' "$BAD" | head -3 | cut -c1-90)
           write \"371 tests green (verified: xcodebuild 2026-08-29)\" or mark it (unverified)"
else
  N=$(grep -cEi "$CLAIM_RE" "$F" 2>/dev/null | tr -d ' ')
  M=$(grep -Ei "$CLAIM_RE" "$F" 2>/dev/null | grep -viE '\((verified|unverified)|unverified' | wc -l | tr -d ' ')
  [ "${M:-0}" -gt 0 ] && warn "$M of $N test-count claims carry no evidence marker (historical entries — do not rewrite; applies to new ones)"
fi

# --- 7. size ------------------------------------------------------------------
CHARS=$(wc -c < "$F" | tr -d ' ')
[ "$CHARS" -gt "$SIZE_WARN" ] && warn "$CHARS characters (soft limit $SIZE_WARN) — move detail into docs/ and reference it by path"

if [ "$ERR" -eq 0 ]; then printf '  OK\n'; else printf '  FAILED\n'; fi
exit "$ERR"
