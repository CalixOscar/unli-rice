#!/bin/sh
#
# check-template-drift.sh
#
# Checks whether the built-in "Engineering Guardrails" House Rules template
# (Sources/UnliRiceCore/HouseRulesPreset.swift) is behind the studio guardrails
# file it is distilled from. Run it before archiving a release.
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
printf '%s\n' "Refresh engineeringGuardrailsBody in $PRESET in generic words (no studio or tool names, under ~1,000 tokens; HouseRulesTests enforces both), then move the guardrails-refreshed-from stamp to the newest guardrails commit."
exit 1
