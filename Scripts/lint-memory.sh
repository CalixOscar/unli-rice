#!/bin/sh
# lint-memory.sh — structural + budget check for memory.md
#
# CANONICAL COPY: ~/Documents/Unli Rice Vault/scripts/lint-memory.sh
# Edit it there and re-run install-studio-hooks.sh.
#
# memory.md is the project's CURRENT WORKING STATE and nothing else: the six
# atomic Handoff fields, plus active gotchas and open hypotheses. It is what an
# agent should be able to read in full at the start of every session without
# thinking about the cost. PROJECT_NOTES.md is the historical record and is not
# bounded; this file is, and the bound is enforced rather than suggested.
#
# Why the cap is an error and not a warning (2026-09-02): PROJECT_NOTES.md has
# carried a soft 40,000-char warning since 2026-08-29 and reached 119,551 chars
# in Unli Rice anyway. A warning that never blocks is a warning nobody acts on.
# 32,000 chars is roughly 8,000 tokens.
#
# Usage:
#   lint-memory.sh [path]            check the whole file
#   lint-memory.sh --staged [path]   content rules apply only to added lines
#
# Exit 1 on error, 0 otherwise. Warnings never block.

STAGED=0
if [ "$1" = "--staged" ]; then STAGED=1; shift; fi
F="${1:-memory.md}"
HARD="${MEMORY_SIZE_MAX:-32000}"
SOFT="${MEMORY_SIZE_WARN:-24000}"
ERR=0
WANT="Status,Task,Files touched,Next step,Gotchas,Left by,"

fail() { printf '  ERROR  %s\n' "$1"; ERR=1; }
warn() { printf '  warn   %s\n' "$1"; }

[ -f "$F" ] || { printf 'lint-memory: no such file: %s\n' "$F"; exit 1; }
printf 'lint-memory: %s%s\n' "$F" "$([ "$STAGED" -eq 1 ] && echo ' (staged mode)')"

allowed() { grep -qF "lint-allow $1 \"$2\"" "$F"; }

# --- 1. budget — the whole point of this file ---------------------------------
CHARS=$(wc -c < "$F" | tr -d ' ')
if [ "$CHARS" -gt "$HARD" ]; then
  fail "$CHARS characters, hard limit $HARD (~$(( HARD / 4 )) tokens).
           memory.md holds current state only. Move finished work into
           PROJECT_NOTES.md's Session Log or Decisions Log, and design detail into
           docs/ referenced by path. Do not raise the limit to make this pass."
elif [ "$CHARS" -gt "$SOFT" ]; then
  warn "$CHARS characters (soft $SOFT, hard $HARD) — compact before it blocks a commit"
fi

# --- 2. no history in here ----------------------------------------------------
# A dated ### heading means Session Log entries have started accumulating in the
# working-state file. That is exactly how PROJECT_NOTES.md got to 119k.
DATED=$(grep -cE '^#{2,3} 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' "$F")
if [ "${DATED:-0}" -gt 0 ]; then
  fail "$DATED dated heading(s) in memory.md — this file is not a log.
           Dated entries belong in PROJECT_NOTES.md under Decisions Log or
           Session Log. (**Left by:** carries the date for current state.)"
fi

# --- 3. the six fields, per track, in order -----------------------------------
# Identical contract to the Handoff section it replaced, deliberately: the fields,
# their order, the atomicity rule and the dated **Left by:** are unchanged, so
# nothing new has to be learned and a half-migrated repo reads the same either way.
# A memory.md may carry several named tracks (### Track — ...) when one codebase
# ships two products; each is validated independently.

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
      fail "$_label: **Left by:** carries no YYYY-MM-DD date — \"Claude Code 2026-09-02\""
    fi
  fi
}

# Fields may sit directly under the title (single track) or under ### tracks.
START=$(grep -n '^# ' "$F" | head -1 | cut -d: -f1)
[ -n "$START" ] || START=0
END=$(( $(wc -l < "$F") + 1 ))

TRACKS=$(awk -v s="$START" 'NR>s && /^### /{print NR}' "$F")
if [ -z "$TRACKS" ]; then
  check_track "$START" "$END" "memory.md"
else
  FIRSTT=$(printf '%s\n' "$TRACKS" | head -1)
  PRE=$(awk -v s="$START" -v e="$FIRSTT" 'NR>s && NR<e && /^\*\*[A-Z][A-Za-z ]*:\*\*/{c++} END{print c+0}' "$F")
  [ "$PRE" -eq 0 ] || fail "$PRE field(s) above the first track heading — a field outside
           every track belongs to no track and will be read as belonging to
           whichever one a reader happens to scroll into"
  set -- $TRACKS
  while [ $# -gt 0 ]; do
    _st=$1; shift
    if [ $# -gt 0 ]; then _en=$1; else _en=$END; fi
    _name=$(sed -n "${_st}p" "$F" | sed 's/^### *//' | cut -c1-44)
    check_track "$_st" "$_en" "track \"$_name\""
  done
fi

# --- 4. claims carry their evidence -------------------------------------------
CLAIM_RE='[0-9]+ tests? (green|passing|pass\b)'
if [ "$STAGED" -eq 1 ]; then
  BAD=$(git diff --cached -U0 -- "$F" | grep '^+' | grep -v '^+++' | sed 's/^+//' \
        | grep -Ei "$CLAIM_RE" | grep -viE '\((verified|unverified)|unverified')
  [ -n "$BAD" ] && fail "new test-count claim without evidence:
           $(printf '%s' "$BAD" | head -3 | cut -c1-90)
           write \"371 tests green (verified: xcodebuild 2026-09-02)\" or mark it (unverified)"
else
  M=$(grep -Ei "$CLAIM_RE" "$F" 2>/dev/null | grep -viE '\((verified|unverified)|unverified' | wc -l | tr -d ' ')
  [ "${M:-0}" -gt 0 ] && fail "$M test-count claim(s) carry no evidence marker.
           Unlike PROJECT_NOTES.md this file is not append-only history, so there
           is nothing here that is too old to fix — fix it."
fi

if [ "$ERR" -eq 0 ]; then printf '  OK (%s chars)\n' "$CHARS"; else printf '  FAILED\n'; fi
exit "$ERR"
