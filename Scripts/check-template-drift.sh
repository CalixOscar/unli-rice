#!/bin/sh
#
# check-template-drift.sh
#
# Checks whether the built-in "Engineering Guardrails" House Rules template
# (Sources/UnliRiceCore/HouseRulesPreset.swift) is behind the studio guardrails
# file it is distilled from. A SHA-256 marker tracks the exact source bytes,
# including uncommitted edits; older presets use commit and dirty-file checks.
# Run it before archiving a release.
#
# This script is specific to this repo. It is NOT one of the studio script
# copies managed by the vault's install-studio-hooks.sh. On machines without
# the guardrails file it skips and exits 0.
#
# Usage: sh Scripts/check-template-drift.sh
# Exit codes: 0 current or skipped, 1 drift, 2 setup error.

set -eu

cd "$(dirname "$0")/.."

PRESET=Sources/UnliRiceCore/HouseRulesPreset.swift
GUARDRAILS_FILE="${GUARDRAILS_FILE:-$HOME/Documents/Unli Rice Vault/_AI Context/04_Guardrails.md}"

stamp=$(sed -n 's/.*guardrails-refreshed-from: \([0-9a-f]\{7,40\}\).*/\1/p' "$PRESET" | head -n 1)
if [ -z "$stamp" ]; then
  echo "check-template-drift: no guardrails-refreshed-from stamp in $PRESET" >&2
  exit 2
fi

# A present marker must be unique and contain exactly one lowercase SHA-256.
markers=$(grep -c 'guardrails-source-sha256' "$PRESET" || true)
digest=
if [ "$markers" -ne 0 ]; then
  digest=$(sed -n 's/^[[:space:]]*\/\/ guardrails-source-sha256: \([0-9a-f]*\)$/\1/p' "$PRESET")
  if [ "$markers" -ne 1 ] || [ "${#digest}" -ne 64 ]; then
    echo "check-template-drift: malformed or duplicate guardrails-source-sha256 marker in $PRESET" >&2
    exit 2
  fi
fi

if [ ! -f "$GUARDRAILS_FILE" ]; then
  printf '%s\n' "check-template-drift: skipped (no guardrails file at $GUARDRAILS_FILE; only the founder's Mac has one)"
  exit 0
fi

gdir=$(dirname "$GUARDRAILS_FILE")
gbase=$(basename "$GUARDRAILS_FILE")

if ! git -C "$gdir" rev-parse --verify --quiet "$stamp^{commit}" >/dev/null; then
  echo "check-template-drift: stamp $stamp is not a commit in the guardrails history ($gdir)" >&2
  exit 2
fi

if [ -n "$digest" ]; then
  actual=$(shasum -a 256 < "$GUARDRAILS_FILE")
  actual=${actual%% *}
  if [ "$actual" = "$digest" ]; then
    printf '%s\n' "check-template-drift: OK (guardrails source matches snapshot $digest; baseline $stamp)"
    exit 0
  fi
  printf '%s\n' "check-template-drift: DRIFT (guardrails source does not match snapshot $digest)"
  printf '%s\n' 'Refresh engineeringGuardrailsBody from the current source, review the wording, then update guardrails-source-sha256 to its SHA-256 and guardrails-refreshed-from to the committed baseline.'
  exit 1
fi

commits=$(git -C "$gdir" log --format='  %h %ad %s' --date=short "$stamp..HEAD" -- "$gbase")
dirty=$(git -C "$gdir" status --porcelain -- "$gbase")

if [ -z "$commits" ] && [ -z "$dirty" ]; then
  printf '%s\n' "check-template-drift: OK (Engineering Guardrails template is current with guardrails commit $stamp)"
  exit 0
fi

printf '%s\n' "check-template-drift: DRIFT (the guardrails changed after the template was refreshed from $stamp)"
if [ -n "$commits" ]; then
  printf '%s\n' "Guardrails commits since then:"
  printf '%s\n' "$commits"
fi
if [ -n "$dirty" ]; then
  printf '%s\n' "Uncommitted edits to $gbase (commit them first, so the stamp can name them)."
fi
printf '%s\n' "Refresh engineeringGuardrailsBody in $PRESET in generic words (no studio or tool names, under ~1,000 tokens; HouseRulesTests enforces both), then update guardrails-refreshed-from to the source baseline and guardrails-source-sha256 to the exact reviewed source SHA-256."
exit 1
