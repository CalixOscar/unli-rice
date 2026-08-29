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
WANT="Status,Task,Files touched,Next step,Gotchas,Left by,"

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

# --- 4/5. Handoff: six fields per track, in order -----------------------------
# A Handoff may carry several named tracks (### Track name — ...). That is a real
# pattern, not sloppiness: UnliDisk ships two App Store products from one codebase
# and keeps a self-contained handoff for each. Each track is validated on its own,
# so a multi-track note is held to the same standard as a single-track one instead
# of being waved through by a blanket waiver.
#
# The one shape that is always wrong is a DATED heading inside Handoff. That means
# the "## Decisions Log" heading below is missing, so every log entry is nesting
# inside Handoff instead of following it. UnliDisk hid 120 entries that way, and
# the old check reported it only as "a field was split around inserted content" —
# true, but it named neither the cause nor the fix. (2026-08-29)

check_track() {
  _s=$1; _e=$2; _label=$3

  _got=$(awk -v s="$_s" -v e="$_e" 'NR>s && NR<e && /^\*\*[A-Z][A-Za-z ]*:\*\*/ {
           match($0, /^\*\*[^:]*:/); print substr($0, 3, RLENGTH-3) }' "$F")

  _dup=$(printf '%s\n' "$_got" | grep -v '^$' | sort | uniq -d | tr '\n' ' ')
  [ -n "$_dup" ] && fail "$_label repeats field(s): $_dup
           two sessions each wrote a field without reconciling the other five —
           the six fields describe one moment in time, so update all six or none"

  _norm=$(printf '%s\n' "$_got" | tr '\n' ',' | sed 's/Files touched[^,]*/Files touched/;s/,,*$/,/')
  [ "$_norm" = "$WANT" ] || fail "$_label fields wrong or out of order.
           expected: $WANT
           found:    $_norm"

  _lb=$(awk -v s="$_s" -v e="$_e" 'NR>s && NR<e && /^\*\*Left by:\*\*/{print}' "$F")
  if [ -z "$_lb" ]; then
    fail "$_label has no **Left by:** field"
  else
    _undated=$(printf '%s\n' "$_lb" | grep -cvE '20[0-9]{2}-[0-9]{2}-[0-9]{2}')
    if [ "${_undated:-0}" -gt 0 ]; then
      fail "$_label: **Left by:** carries no YYYY-MM-DD date — \"Claude Code 2026-08-29\""
    else
      _seen=$(printf '%s\n' "$_lb" | grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' | sort | tail -1)
      [ -n "$NEWEST" ] && [ "$_seen" \< "$NEWEST" ] && \
        warn "$_label: **Left by:** is $_seen but the newest dated entry is $NEWEST — stale Handoff?"
    fi
  fi
}

HSTART=$(grep -n '^## Handoff' "$F" | head -1 | cut -d: -f1)
NEWEST=$(grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$F" | sort | tail -1)

if [ -n "$HSTART" ]; then
  HEND=$(awk -v s="$HSTART" 'NR>s && /^## /{print NR; exit}' "$F")
  [ -n "$HEND" ] || HEND=$(( $(wc -l < "$F") + 1 ))

  DATED=$(awk -v s="$HSTART" -v e="$HEND" 'NR>s && NR<e && /^### 20[0-9][0-9]-/{c++} END{print c+0}' "$F")
  if [ "$DATED" -gt 0 ]; then
    fail "Handoff contains $DATED dated entry heading(s) between lines $HSTART and $HEND.
           Handoff holds only current state; dated entries belong under a later
           heading. The '## Decisions Log' heading is almost certainly missing, so
           the log is nesting inside Handoff. Insert it above the first dated entry."
  fi

  TRACKS=$(awk -v s="$HSTART" -v e="$HEND" 'NR>s && NR<e && /^### /{print NR}' "$F")
  if [ -z "$TRACKS" ]; then
    check_track "$HSTART" "$HEND" "Handoff"
  else
    FIRSTT=$(printf '%s\n' "$TRACKS" | head -1)
    PRE=$(awk -v s="$HSTART" -v e="$FIRSTT" 'NR>s && NR<e && /^\*\*[A-Z][A-Za-z ]*:\*\*/{c++} END{print c+0}' "$F")
    [ "$PRE" -eq 0 ] || fail "Handoff has $PRE field(s) above its first track heading — a field
           outside every track belongs to no track and will be read as belonging to
           whichever one a reader happens to scroll into"
    set -- $TRACKS
    while [ $# -gt 0 ]; do
      _st=$1; shift
      if [ $# -gt 0 ]; then _en=$1; else _en=$HEND; fi
      _name=$(sed -n "${_st}p" "$F" | sed 's/^### *//' | cut -c1-44)
      check_track "$_st" "$_en" "Handoff track \"$_name\""
    done
  fi
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
