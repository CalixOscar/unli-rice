#!/bin/sh
# check-secrets.sh — staged-diff scan for secrets, private notes, and client data
#
# CANONICAL COPY: ~/Documents/Unli Rice Vault/scripts/check-secrets.sh
# Edit it there and re-run install-studio-hooks.sh.
#
# Backs the guardrails' backend security floor rule 1 ("no secrets in the binary
# or the repo") with something that runs whether or not the committing tool read
# the guardrails, and the vault/repo boundary (vendor rate cards, client contacts
# and personal notes stay in the vault, never in a repo that may go public).
#
# Deliberate severity split, so this stays worth having:
#   ERROR   — staging a private path, or a value that is shaped like a live
#             credential. Both are unambiguous and both are expensive to undo,
#             because a secret that reaches git history is compromised even after
#             the commit is amended.
#   warn    — email addresses and phone numbers in added lines. Real leaks look
#             like this, but so do LICENSE files, changelogs and code comments.
#             Erroring on these is how a hook trains you into --no-verify, which
#             discards the ERROR checks above at the same time.
#
# Waiving a known-safe match: add the literal string on its own line in
# .studio-secrets-allow at the repo root (comments start with #).
#
# Usage: check-secrets.sh [--staged]   (--staged is the only supported mode today;
#                                       the flag is accepted for symmetry with the
#                                       other studio linters)

ERR=0
ALLOW=".studio-secrets-allow"
fail() { printf '  ERROR  %s\n' "$1"; ERR=1; }
warn() { printf '  warn   %s\n' "$1"; }

printf 'check-secrets: staged changes\n'

FILES=$(git diff --cached --name-only --diff-filter=ACMR)
[ -n "$FILES" ] || { printf '  OK (nothing staged)\n'; exit 0; }

allowed() {
  [ -f "$ALLOW" ] || return 1
  grep -v '^[[:space:]]*#' "$ALLOW" | grep -v '^[[:space:]]*$' | while IFS= read -r pat; do
    case "$1" in *"$pat"*) echo hit; return ;; esac
  done | grep -q hit
}

# --- 1. private paths must never be staged ------------------------------------
# These are the studio's universal private directories. They are in the global
# gitignore, so a file appearing here means it was force-added or the pattern was
# overridden locally — worth stopping for either way.
PRIV=$(printf '%s\n' "$FILES" | grep -E '(^|/)(private|client-notes)/|\.private\.md$|(^|/)\.env($|\.)' \
       | grep -vE '\.env\.(example|sample|template)$')
if [ -n "$PRIV" ]; then
  fail "private path(s) staged:
$(printf '%s\n' "$PRIV" | sed 's/^/             /')
           private/ and client-notes/ hold vendor rates, client contacts and
           personal notes. They belong in the vault, not in a repo. Unstage with
           'git restore --staged <path>' — do not commit and delete afterwards."
fi

# --- 2. credential-shaped values in added lines -------------------------------
ADDED=$(git diff --cached -U0 --diff-filter=ACMR -- $(printf '%s\n' "$FILES" | grep -v "^$ALLOW$") 2>/dev/null \
        | grep '^+' | grep -v '^+++' | sed 's/^+//')

# Prefixed provider tokens are near-zero-false-positive: the prefix IS the claim.
SECRET_RE='sk-[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AIza[A-Za-z0-9_-]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|glpat-[A-Za-z0-9_-]{20,}|sq0(atp|csp)-[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
# Assignment of a long opaque value to a key-shaped name. Excludes obvious
# placeholders, and excludes hashes/UUIDs, which are long but not credentials.
ASSIGN_RE='(api[_-]?key|secret|token|passwd|password|client[_-]?secret|access[_-]?key|auth)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9/+_-]{24,}["'"'"']'
PLACEHOLDER='YOUR_|XXX|<[a-z]|example|placeholder|dummy|redacted|changeme|\.\.\.|\$\{|process\.env|ProcessInfo'

# A line matching both patterns (a prefixed token assigned to a key-named var is
# the common case) is one finding, not two — deduplicate before reporting.
HITS=$(printf '%s\n' "$ADDED" | grep -EIi "$SECRET_RE|$ASSIGN_RE" | grep -viE "$PLACEHOLDER" | sort -u)

printf '%s\n' "$HITS" | while IFS= read -r l; do
  [ -n "$l" ] || continue
  if allowed "$l"; then
    printf '  waived %s\n' "$(printf '%s' "$l" | cut -c1-72)"
  else
    printf '  ERROR  credential-shaped value in an added line:\n             %s\n' \
      "$(printf '%s' "$l" | cut -c1-100)"
    echo x >> .secrets-lint-err
  fi
done
[ -f .secrets-lint-err ] && {
  ERR=1; rm -f .secrets-lint-err
  printf '           A key that must ship in a client has to be provider-restricted\n'
  printf '           to the bundle ID and one API — gitignoring it is not enough,\n'
  printf '           because the value still ships inside the app. If this is a false\n'
  printf '           positive, add the literal string to %s.\n' "$ALLOW"
}

# --- 3. contact details — warn, never block -----------------------------------
MAIL=$(printf '%s\n' "$ADDED" | grep -EoI '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
       | grep -viE 'noreply|no-reply|example\.(com|org)|@(anthropic|apple)\.com|calmdownoscar\.com' \
       | sort -u)
if [ -n "$MAIL" ]; then
  warn "email address(es) in added lines — confirm these are not a client's:
$(printf '%s\n' "$MAIL" | head -5 | sed 's/^/             /')"
fi

if [ "$ERR" -eq 0 ]; then printf '  OK\n'; else printf '  FAILED\n'; fi
exit "$ERR"
