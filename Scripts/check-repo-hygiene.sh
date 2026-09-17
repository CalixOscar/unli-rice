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

# --- 1. plans and intents live in the repo's plans directory ----------------
# An ERROR, not a warning: the fix is one `git mv` and costs nothing, whereas a
# plan filed in the wrong place is found by nobody and silently superseded.
# Waive in-file with:
#   <!-- lint-allow plan-location "reason, date" -->
#
# 2026-09-06, Nuptia. This rule hardcoded docs/ and rejected a plan filed in
# documentation/ — beside the other six plans and the audit that plan cites by
# path. The suggested fix would have created a second, near-empty plans
# directory and split the artifact chain the rule exists to protect. The rule is
# "plans live together where this repo keeps them", not "plans live in a
# directory named docs". So: accept either name, and suggest the one the repo
# already uses. A repo with both keeps docs/ as the canonical target.
if [ -d docs ]; then
  PLANS_DIR=docs
elif [ -d documentation ]; then
  PLANS_DIR=documentation
else
  PLANS_DIR=docs
fi

STRAY=$(git diff --cached --name-only --diff-filter=A \
        | grep -E '(^|/)(PLAN|INTENT)[-_][^/]*\.md$' \
        | grep -vE '^(docs|documentation)/')
for f in $STRAY; do
  [ -n "$f" ] || continue
  if [ -f "$f" ] && grep -qF 'lint-allow plan-location' "$f"; then
    printf '  waived %s (plan-location)\n' "$f"
    continue
  fi
  case "$f" in
    INTENT[-_]*|*/INTENT[-_]*) want="$PLANS_DIR/intent/$(basename "$f")" ;;
    *)                         want="$PLANS_DIR/$(basename "$f")" ;;
  esac
  fail "$f is a plan/intent doc outside $PLANS_DIR/
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
# EVERY project file, not the first one the glob happens to return. iCloud leaves
# duplicates like "UnliRice 2.xcodeproj" beside the real one, and `head -1` picked a
# stale copy — which reported a file as missing that had just been regenerated into
# the live project. A check that cries wolf is the one people learn to ignore.
PBX_LIST=$(ls -1d ./*.xcodeproj 2>/dev/null || true)
if [ -n "$PBX_LIST" ]; then
  MISSING=""
  for f in $(git diff --cached --name-only --diff-filter=A | grep -E '^Sources/.*\.swift$'); do
    base=$(basename "$f")
    found=0
    for proj in $PBX_LIST; do
      [ -f "$proj/project.pbxproj" ] || continue
      grep -qF "$base" "$proj/project.pbxproj" && { found=1; break; }
    done
    [ "$found" -eq 1 ] || MISSING="$MISSING $base"
  done
  DUPES=$(printf '%s\n' "$PBX_LIST" | grep -cE ' [0-9]+\.xcodeproj$' || true)
  [ "${DUPES:-0}" -gt 0 ] && warn "$DUPES duplicate .xcodeproj folder(s) beside the real one
           iCloud collision copies (\"Name 2.xcodeproj\"). Harmless to delete — the
           project is generated from project.yml — but they confuse tools that glob."

  if [ -n "$MISSING" ]; then
    warn "new source file(s) not in the Xcode project:$MISSING
           swift build globs the directory and will pass; Xcode carries a fixed file
           list and will fail with \"Cannot find 'X' in scope\". Regenerate first:
             xcodegen generate"
  fi
fi

# --- 3. stage 1.5: was the intent read before the plan was written? ----------
# A WARNING, never an error. Compare rule 1: a misfiled plan is fixed by one
# `git mv`, so blocking costs nothing. Skipping the intent read is fixed by going
# and running an Astra pass, which is not free — and refusing the commit would
# block the plan from being recorded at all, which is backwards for the same
# reason branch drift below only warns.
#
# Why this exists (2026-09-18). Stage 1.5 was added to the guardrails: Astra
# attacks docs/intent/INTENT-00N-<slug>.md before Claude plans from it, because
# nothing else in the chain ever attacked the intent. The template grew an
# `**Intent read:**` field to record whether that happened. A template field is
# prose — see this file's header for what prose is worth. This makes a skipped
# gate visible at the moment a plan lands, which is the last point where running
# it is still cheap.
#
# Waive in-file (in the PLAN) with:
#   <!-- lint-allow intent-read "reason, date" -->
for f in $(git diff --cached --name-only --diff-filter=AM \
           | grep -E '^(docs|documentation)/PLAN[-_][^/]*\.md$'); do
  [ -f "$f" ] || continue
  if grep -qF 'lint-allow intent-read' "$f"; then
    printf '  waived %s (intent-read)\n' "$f"
    continue
  fi

  # PLAN-<slug>.md  ->  INTENT-00N-<slug>.md
  slug=$(basename "$f" .md | sed -E 's/^PLAN[-_]//')
  intent=$(ls -1 "$PLANS_DIR"/intent/INTENT*"$slug"*.md 2>/dev/null | head -1)

  if [ -z "$intent" ]; then
    warn "$f has no matching intent doc in $PLANS_DIR/intent/
           Looked for: $PLANS_DIR/intent/INTENT-00N-$slug.md
           The chain is intent -> plan -> build. A plan with no intent doc has no
           record of what was actually asked for, and nothing for a stage-5 swarm
           escalation to be checked against. Template: scripts/templates/INTENT.md"
    continue
  fi

  read_state=$(grep -m1 '^\*\*Intent read:\*\*' "$intent" | sed -E 's/^\*\*Intent read:\*\*[[:space:]]*//')
  case "$read_state" in
    '')
      warn "$(basename "$intent") has no **Intent read:** field
           It predates stage 1.5 or was not written from the current template.
           Add:  **Intent read:** not run | passed YYYY-MM-DD | superseded by INTENT-00M" ;;
    'not run'*|*'|'*)
      # unedited template line still carries the '|' separators
      warn "stage 1.5 not recorded as run for $(basename "$intent")
           $f is being committed from an intent nothing has attacked. Astra's read
           (plus the 08_AI_Failure_Modes lens list) is the only gate on the intent
           itself — stage 3 attacks the plan, not what the plan was built from.
           Run it, then set:  **Intent read:** passed $(date +%Y-%m-%d)
           Deliberate skip? Add to $f:
           <!-- lint-allow intent-read \"reason, $(date +%Y-%m-%d)\" -->" ;;
  esac
done

# a new intent doc should carry the field at all
for f in $(git diff --cached --name-only --diff-filter=A \
           | grep -E '^(docs|documentation)/intent/INTENT[-_][^/]*\.md$'); do
  [ -f "$f" ] || continue
  grep -qF 'lint-allow intent-read' "$f" && continue
  grep -q '^\*\*Intent read:\*\*' "$f" || \
    warn "$f is missing the **Intent read:** field
           Stage 1.5 has nowhere to record itself. Copy the header block from
           scripts/templates/INTENT.md"
done

# --- 4. branch drift ---------------------------------------------------------
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
