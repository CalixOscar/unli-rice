#!/bin/sh
# check-repo-hygiene.sh — catch a session drifting off its own plan
#
# CANONICAL COPY: ~/Documents/Unli Rice Vault/scripts/check-repo-hygiene.sh
# Edit it there and re-run install-studio-hooks.sh.
#
# Why this exists (2026-09-02). `PLAN-languages-and-append.md` ended with a Handoff
# section carrying two explicit instructions: write the plan to
# `docs/PLAN-languages-and-append.md`, and work on a fresh branch off main. The plan
# landed at the repo root instead, and the build (79eee2f) landed on top of 21
# unrelated commits on `feature/languages-and-append`. Both rules were written down,
# in the right document, by the right tool, and neither bound anything.
#
# That is the whole argument for this file. Prose is advisory; a hook is not.
#
# Usage: check-repo-hygiene.sh [--staged]
# Exit 1 on error, 0 otherwise. Warnings never block.

ERR=0
fail() { printf '  ERROR  %s\n' "$1"; ERR=1; }
warn() { printf '  warn   %s\n' "$1"; }

printf 'check-repo-hygiene: staged changes\n'

# --- 1. plans and intents live in docs/ -------------------------------------
# An ERROR, not a warning: the fix is one `git mv` and costs nothing, whereas a
# plan filed in the wrong place is found by nobody and silently superseded.
# Waive in-file with:
#   <!-- lint-allow plan-location "reason, date" -->
STRAY=$(git diff --cached --name-only --diff-filter=A \
        | grep -E '(^|/)(PLAN|INTENT)[-_][^/]*\.md$' \
        | grep -vE '^docs/')
for f in $STRAY; do
  [ -n "$f" ] || continue
  if [ -f "$f" ] && grep -qF 'lint-allow plan-location' "$f"; then
    printf '  waived %s (plan-location)\n' "$f"
    continue
  fi
  case "$f" in
    INTENT[-_]*|*/INTENT[-_]*) want="docs/intent/$(basename "$f")" ;;
    *)                         want="docs/$(basename "$f")" ;;
  esac
  fail "$f is a plan/intent doc outside docs/
           The artifact chain expects it at: $want
           Fix:  mkdir -p $(dirname "$want") && git mv \"$f\" \"$want\"
           A plan filed somewhere else is one nobody finds — see the guardrails'
           artifact chain. Deliberate exception? Add to the file:
           <!-- lint-allow plan-location \"reason, 2026-09-02\" -->"
done

# --- 2. a new source file that the Xcode project has never heard of ----------
# Warns, does not block: not every repo generates its project, and a file can be
# legitimately added in one commit and wired up in the next.
#
# This exists because it has now happened twice in one day. `swift build` and
# `swift test` glob the source directory, so a new file compiles and its tests pass
# — while the checked-in .xcodeproj still carries a fixed file list and fails with
# "Cannot find 'X' in scope". The SPM build being green is what makes it invisible.
PBX=$(ls -1 ./*.xcodeproj/project.pbxproj 2>/dev/null | head -1)
if [ -n "$PBX" ]; then
  MISSING=""
  for f in $(git diff --cached --name-only --diff-filter=A | grep -E '^Sources/.*\.swift$'); do
    base=$(basename "$f")
    grep -qF "$base" "$PBX" || MISSING="$MISSING $base"
  done
  if [ -n "$MISSING" ]; then
    warn "new source file(s) not in the Xcode project:$MISSING
           swift build globs the directory and will pass; Xcode carries a fixed file
           list and will fail with \"Cannot find 'X' in scope\". Regenerate first:
             xcodegen generate"
  fi
fi

# --- 3. branch drift ---------------------------------------------------------
# A WARNING and deliberately not an error. Refusing a commit because a branch has
# grown would block the one action that makes work recoverable, which is exactly
# backwards. The job here is to be seen at commit 3 rather than discovered at 22.
DRIFT_AT="${BRANCH_DRIFT_WARN:-8}"
BR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

if [ -n "$BR" ] && [ "$BR" != "HEAD" ]; then
  # Resolve the trunk: origin/HEAD if it is set, else main, else master.
  BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -z "$BASE" ]; then
    for c in main master; do
      git show-ref --verify --quiet "refs/heads/$c" && { BASE="$c"; break; }
    done
  fi

  if [ -n "$BASE" ] && [ "$BR" != "$BASE" ] && [ "$BR" != "${BASE#origin/}" ]; then
    AHEAD=$(git rev-list --count "$BASE..HEAD" 2>/dev/null || echo 0)
    UP=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
    # Commits that exist on no remote at all — the number that describes real loss.
    UNBACKED=$(git rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)

    if [ "$AHEAD" -ge "$DRIFT_AT" ]; then
      warn "$BR is $AHEAD commits ahead of $BASE (threshold $DRIFT_AT).
           A plan that said \"fresh branch off main\" is how this branch got to 22.
           If this commit belongs to different work, branch now — it is cheap here
           and expensive later:  git switch -c <name> $BASE"
    fi
    if [ "$UNBACKED" -ge "$DRIFT_AT" ]; then
      warn "$UNBACKED commit(s) on this branch exist on NO remote.
           $([ -z "$UP" ] && echo 'This branch has no upstream.' || echo "Upstream is $UP.")
           One disk is one point of failure:  git push -u origin $BR"
    fi
  fi
fi

if [ "$ERR" -eq 0 ]; then printf '  OK\n'; else printf '  FAILED\n'; fi
exit "$ERR"
