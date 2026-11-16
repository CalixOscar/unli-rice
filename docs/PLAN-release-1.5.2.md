# PLAN — Mac 1.5.2 release

**Intent:** release the already-built compact retrieval and maintenance changes. Founder, 2026-11-16: "publish the new build on github and app store"; then "waive the post mortem I believe it has already been run? Also resolve the bundled guardrails template".
**Scope:** Mac only. No Capture release, new feature, data migration or automatic changes to saved House Rules.
**Stage:** release preparation; not yet shippable.
**Branch:** `release/mac-1.5.2`, based on `f7dfc86`.

## Authorization and gates

The founder waived the six-month release failure analysis for this release in the words quoted above. Earlier analysis: `docs/release/1.5-premortem.md`; compact retrieval's technical post-mortem: `docs/dialogue/compact-retrieval.md`. This waiver does not waive build, test, review or screenshot checks.

The implementation is already covered by INTENT-014, SPEC-compact-retrieval and PLAN-compact-retrieval. The template refresh below is tier-1 maintenance under the authoritative guardrails: no new intent/spec/pre-mortem for that edit. Release metadata adds no application behavior. Existing `AGENTS.md` edits belong to another session and must remain unstaged.

## Steps and acceptance

- [x] T1 — refresh the generic Engineering Guardrails preset, under 1,000 estimated tokens. Preserve note safety, review-before-checkpoint and planner ownership. Include current security/privacy, measurable performance, journey and design-choice guidance, the repo's full verification gate and safe workspace retirement. No saved notes or drafts change.
- [x] T2 — make `Scripts/check-template-drift.sh` compare an optional SHA-256 fingerprint of the exact source bytes. Keep the commit marker as provenance and preserve legacy commit-based checks when no fingerprint exists. A mismatch fails even if Git is clean; matching uncommitted source is valid. Missing source still skips. Do not change or commit the vault. Verify matching, changed, absent, legacy and malformed fingerprint cases in disposable fixtures.
- [x] R1 — confirm live Apple inventory, then set Mac app, helper and widget to 1.5.2 (14); leave Capture unchanged. Live 2026-11-16: Mac 1.5.1 Ready for Distribution, latest TestFlight 1.5.1 (13), uploaded Nov 3. Recheck before archive.
- [x] R2 — review diff, run full Swift tests outside sandbox, template drift check and a universal Mac Release build. Baseline f7dfc86: 694 tests, 0 failures, 2 skips and universal Release build pass outside sandbox, 2026-11-16. Sandboxed attempts fail on file coordination and compiler macro access; these are not accepted release evidence.
- [x] R3 — refresh screenshot 05 from disposable demo data; review screenshots against the candidate. No founder notes in screenshots. Verify existing journeys affected by the To Do correction and template selection; mark gaps explicitly.
- [ ] R4 — archive, verify nested versions/signatures/entitlements, export a distribution package and upload. Verify Apple's processing result separately from local success.
- [ ] R5 — publish a GitHub release from the exact reviewed commit, with honest release notes and appropriate distributable artifact. Create/save Apple version metadata, attach eligible build, submit for review and verify state. Keep existing pricing and release preferences.

## Template source tracking design

The source guardrails currently have authorized but uncommitted edits. A commit stamp alone cannot identify that text. Add `guardrails-source-sha256: <64 lowercase hex>` beside `guardrails-refreshed-from: 0112345`; the fingerprint identifies exact bytes, while the commit records the source's committed baseline. New fingerprints are validated before comparison; never treat a malformed value as legacy. A subsequent source edit must fail the check. The source text stays private; only generic distilled instructions and its fingerprint enter this repository.

## Evidence and remaining work

Apple draft 1.5.2 exists. Local archive and distribution export succeeded; no upload, submission or GitHub release yet. Saved notes and existing drafts are unchanged.

2026-11-16 verification: final full Swift suite 694 run, 0 failures, 2 skipped; universal Mac Release build succeeded. Independent planner drift fixtures 7/7 passed. One intermediate full-suite failure required restoring the established Exception Guardrail heading; fixed and full suite rerun. Apple draft 1.5.2 created; nothing uploaded/submitted.

Independent Claude Opus 5.5 review (run run_28130c9989c7, dispatch ctx_f6af92cf568b) found no blockers. Reviewer verified the fixed manifest, 19 script fixture cases and 24 focused tests. Three nonblocking findings: older saved template text is correctly retained but labelled Your own rules (body equality lookup; explained in release notes); checker guidance now names both fingerprint and commit baseline; stale plan status corrected. Original report preserved in docs/dialogue/release-1.5.2.md.

R3: screenshot05 captured from isolated actual candidate UI and visually inspected; 2560x1600 JPEG without alpha. Done returned to the app with unchanged disposable event-log digest. Other full production journeys, accessibility and live cloud sync were not rerun for this maintenance release (unverified). To Do fix is covered by the existing full suite; no live project data was used for UI verification.

R4 local evidence: archive and export succeeded, nested strict signature verification passed on archive and exported payload, app/helper/widget versions all1.5.2(14), lipo confirms x86_64 and arm64. Exported package at /tmp/unlirice-release-1.5.2/export/Unli Rice.pkg; SHA-2568f9647c4240add33d6544a1d7cc7d0c66b5b8cddae4456c950916a1448f8a770. Installer signature checked. Agent/CLI are tool binaries, embedded and included in strict nested signature audit; they have no separate app-version metadata. Apple processing remains unverified until upload.

Final independent recheck ctx_1ae12cdf2ce5: safe to merge and proceed with authorized release; all findings addressed. R3 checkbox and temporary audit status corrected. Recheck verified architectures of all four executables, screenshot dimensions/content, package hash and archive signatures. Supervisor separately verified exported-payload signatures and entitlements.
