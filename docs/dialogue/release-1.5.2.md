# Dialogue — release-1.5.2

**Plan:** docs/PLAN-release-1.5.2.md
**Planner:** codex
**Reviewer:** claude
**State:** built

## claude — independent review — 2026-11-16

Verbatim reviewer report from Orca dispatch ctx_f6af92cf568b, copied by Codex without altering the review:

# Independent review — Mac 1.5.2 release maintenance (task_0e51654f81d4)

Reviewer: Claude Code, model claude-opus-5-5 (Opus 5.5); effort setting not observable. Read-only; no repo, vault, note or external writes.

## Snapshot
- HEAD = f7dfc86763cabb7943de17badcf96d8f32f22863 (matches manifest base).
- All 5 manifest SHA-256 hashes match (preset, script, project.yml, plan, what's-new).
- Live `git diff -- Sources Scripts project.yml` is identical to /tmp/unlirice-release-review.patch (ignoring index lines).
- Also untracked in the tree, not in scope: Screenshots/AppStore-Mac-2026-11-16/.

## Verdict
No blockers. Script preserves meaningful drift detection (it's stricter than before: any byte change fails, even when Git is clean). The release can proceed to visual/signing checks.

## Should-fix (non-blocking)
1. Sources/UnliRice/Studio/GuardrailsGroundingView.swift:146: the active preset name comes from comparing the normalized body. Anyone who applied the old Engineering Guardrails text will now see "Your own rules" instead of "Engineering Guardrails" after upgrading. No data changes, and the what's-new line ("choose the template if you want the new wording") is accurate, but it is a visible change. Check this in R3 (template-selection journey) and consider one plain sentence in the notes.
2. Scripts/check-template-drift.sh:62 prints no fix-it guidance on a fingerprint DRIFT. Line 82 (legacy branch) says to move only the commit stamp and never mentions updating `guardrails-source-sha256`. A future refresher could bump the stamp and leave a stale digest, and the check would still (correctly) fail, but without telling them why.
3. docs/PLAN-release-1.5.2.md, "Evidence and remaining work": "No new archive, upload, version or GitHub release yet" contradicts "Apple draft 1.5.2 created" in the next paragraph. T2 also names `scripts/check-template-drift.sh`, but the real path is `Scripts/`.
4. Info: the template is about 930 of 1,000 estimated tokens ((3,760 bytes incl. indentation + 3)/4). Little room for future additions.

## Commands and results
- `shasum -a 256` on the 5 files: all match the manifest.
- `shasum -a 256 < 04_Guardrails.md` = ac47f99f…cd97, equal to the marker. The guardrails file is uncommitted (`M`). 0112345 resolves to 0112345b71cb… ("one check command per repo", 2026-11-10), with 0 guardrails commits after it.
- `sh Scripts/check-template-drift.sh` (live, read-only) → exit 0, "OK (guardrails source matches snapshot …; baseline 0112345)".
- 19 disposable fixture cases (scratchpad git repos, copied script):
  - hash clean match 0; old hash vs dirty source 1; hash = dirty bytes 0; same bytes later committed 0; edit after hash 1; missing source 0 (skip)
  - uppercase / 63 / 65 chars / trailing space / CRLF / duplicate / empty → 2
  - valid marker + missing source → 0 (skip); bad marker + missing source → 2 (validated before the skip)
  - valid hash + bogus stamp → 2
  - legacy: newer commit 1, clean current 0, dirty 1
- `sh -n` OK; shellcheck isn't installed, so no lint ran.
- `swift test --scratch-path /tmp/urr-review-build-<pid> --filter 'HouseRulesTests|ProfileAndMirrorTests'` → 24 tests, 0 failures (scratch removed afterwards).
- Planner logs: tests log shows "Executed 694 tests, with 2 tests skipped and 0 failures". The suite started 13:31:03, after the last edit to the scoped files (preset 13:30:38). The build log has ONLY_ACTIVE_ARCH=NO, ARCHS arm64 x86_64 and "** BUILD SUCCEEDED **" at 13:32.
- project.yml: unlirice-mcp, UnliRiceWidget and UnliRice are at 1.5.2 (14). UnliRiceCapture and its widget are unchanged at 1.3.1 (13).
- Release claims:
  - To Do fix 0186005 is not an ancestor of the 1.5.1 source merge ae548c7 or of v1.5, so it really is new in 1.5.2.
  - The 24% / 77% / 24-task figures match docs/BENCH-compact-retrieval.md:23-30.
  - Both tools exist in ToolCatalog.swift.

## Unverified
- I did not rerun the full suite or the Release build myself; I relied on the planner logs above.
- The architectures inside the final binary (lipo), signing, entitlements, archive, upload and Apple processing.
- Live Apple inventory.
- Whether unlirice-agent / unlirice-cli (no MARKETING_VERSION in project.yml) are embedded and need versions. This predates this change.
- Screenshot 05 and the UI journeys.
- I did not read the guardrails file's contents; I checked only its hash and history.

## codex — response — 2026-11-16

All three nonblocking findings addressed without changing runtime behavior: document the old-body label, add exact-source fingerprint repair guidance to both script failure branches, correct the plan status and path casing. Screenshot and distribution/signature checks completed separately after the original snapshot, as the plan records. No saved-note or draft migration added. Request scoped recheck of these changes before merge.

## claude — scoped recheck — 2026-11-16

# Recheck — Mac 1.5.2 (task_ddfca22d2ecf)

Reviewer: Claude Code, model claude-opus-5-5 (Opus 5.5); effort setting not observable. Read-only.

## Snapshot
- All 6 recheck manifest hashes match; HEAD is f7dfc86.
- HouseRulesPreset.swift and project.yml have the same hashes as the first reviewed snapshot.

## Earlier findings
1. Script guidance: addressed.
   - The only change is two message lines: a new line 63 on the fingerprint DRIFT branch (before `exit 1`) and a reworded line 83 on the legacy branch. Both now name the digest and the commit baseline.
   - I diffed it against my reviewed copy (sha 48ddc554…). No logic changed.
   - `sh -n` OK. Live check: exit 0, OK against ac47f99f… / 0112345.
   - Fixture replay with the new script: match 0, mismatch 1 (new guidance printed), duplicate 2, legacy-dirty 1, legacy-clean 0, missing 0.
2. "Your own rules" label: addressed. The what's-new copy says older saved template text may now be labelled "Your own rules" and its contents are kept.
3. Plan path and status: addressed. The path now reads `Scripts/`, and the evidence section is consistent: the draft exists, local archive and export are done, and there has been no upload, submission or GitHub release.

## New items (non-blocking)
- docs/PLAN-release-1.5.2.md: the R3 checkbox is still `[ ]`, although the evidence section and the screenshot README record R3 as done (with gaps marked unverified). Tick it, or note what is still open. R4 is correctly open until upload.
- /tmp/unlirice-release-1.5.2/audit.json is out of date. Its timestamp is 13:44, and it still says "preview: no accessibility window; screenshot unverified" and "independent_review: … blocked on Claude quota". Both contradict the later README and plan. It isn't shipped, but don't cite it as release evidence until it's refreshed. Its version, build and package-hash fields are correct.

## Spot checks
- Package SHA-256 8f9647c4…a770 matches the audit and the plan.
- `pkgutil --check-signature`: signed with "3rd Party Mac Developer Installer … (22SNGN5JYD)", the right certificate type for a Mac App Store upload.
- `codesign --verify --deep --strict` passes on the archive app. Its Info.plist is 1.5.2 (14).
- `lipo -archs`: UnliRice, unlirice-mcp, unlirice-agent and unlirice-cli are all x86_64 arm64. The widget appex is present.
- The archive was built at about 13:37, after the last runtime-source edit (preset at 13:30). Later edits touched only checker messages and docs, so the binary matches the reviewed runtime source.
- Screenshot 05: 2560×1600 JPEG, no alpha. It shows the House Rules template gallery with the Engineering Guardrails preview (~928 tokens, 3,711 characters) and the new wording. There is no personal content and nothing clipped.

## Verdict
Safe to merge and go ahead with the already-authorized upload and release. Before the paperwork commit, fix the R3 checkbox, and refresh audit.json or stop citing it.

## Unverified
- Apple processing, entitlement contents and exported-payload signatures. I checked the archive and the installer signature only.
- I did not rerun the full suite, as instructed.

## codex — accepted — 2026-11-16

Recheck accepted. R3 checkbox and temporary audit refreshed as requested; no runtime source change. Independent review gate satisfied. Proceeding with already-authorized publication.
