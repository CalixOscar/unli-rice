# Production Studio release readiness — 2026-11-03

Scope: existing Unli Rice macOS and Unli Rice Capture iOS releases, not the separate open-source workspace proposal. Founder explicitly requested returning to publishing both apps with new iCloud settings. This record is a bounded prelaunch assessment, not a claim that either public update has been submitted.

## Evidence and remaining gates

- Mac 1.5.1 (13) uploaded, processed, installed via TestFlight; actual original capture receipt and explicit approved connection migration are recorded at aa91d60. Fresh installed MCP worked without binding error; an old registered process required reconnect. Live ASC recheck on this resumed pass shows Ready to Submit.
- No `Sources/` or `project.yml` drift from Mac archive checkpoint 087cb0a through 724638b (read-only git diff, this pass). Prior signature, production entitlement, universal architecture and test results remain in the production plan; they were not rerun here.
- Current installed Mac app independently rechecked this pass: bundle `com.calmdownoscar.unlirice`, 1.5.1 (13), NativeCloudEnvironment Production; host deep/strict codesign validation passed including helpers/widget/CLI binaries. This is verification of the installed TestFlight app, not a new archive.
- Capture public version is 1.1 Ready for Distribution. Live TestFlight inventory shows 1.3 (9) Internal/Ready to Test, build 8 Ready to Submit and build 7 Missing Compliance; build 9 has no tester group. Source includes later UI/privacy/migration work than uploaded internal-only 1.3 (9). Do not submit that old artifact as this release. Candidate build 10 is the next observed unused counter, pending complete upload-inventory and exact signed candidate checks.
- Capture's three concealed-editor XCUI queries remained unresolved after matched diagnostics. Native hidden/AX flags and draft preservation are positive evidence, not actual VoiceOver traversal. No claim of either confirmed disclosure or verified exclusion. Independent accessibility and exact phone-candidate voice/sync acceptance remain open.
- Local privacy/reviewer text already explains optional cloud transfer. APP_STORE_SUBMISSION.md's unconditional “no cloud sync” paragraph was corrected in this pass. Public main initially had the old July policy; a target-only GitHub contents update published the reviewed local policy in commit `e74bc25274a6518226a2c8e2405a4b4cf611c302`. Fresh GitHub file read confirmed exact content match, blob `c25d6422e1bf26f6f87e94bf0ccb207b8d2e3476`, including Optional iCloud sync. Canonical URL remains `https://github.com/CalixOscar/unli-rice/blob/main/PRIVACY.md`. No source branch was pushed. Actual store descriptions, screenshots and App Privacy disclosures still require current inspection; local copy alone does not update them.
- No permanent delete, account reset, old cursor removal, new privacy-source workaround or bypass of the explicit migration flow is part of release preparation.

## Hypothetical six-month failure analysis

These are risks and proposed controls, not measured launch outcomes or market facts. Existing pricing and historical conversion data have not been independently rechecked here; no revenue/download claim is made.

1. **Intent versus reality:** users record ideas but do not see them in their AI session, then stop trusting capture. The connector requires installation and the assistant must request context; a working cloud transfer does not guarantee an automatic reminder. Keep onboarding/release language bounded and test receipt plus fresh context rather than snapshots alone.
2. **Distribution and onboarding friction:** an older development link pauses on a production build; repeated retry without explanation looks like data loss. The shipped explicit move/recovery flow must be visible, preserve history and explain account mismatches. Verify the exact installed candidate, not a debug build or source-only test.
3. **Value versus monetary/cognitive cost:** users may expect both apps and assistants to connect without configuration. Current price is unverified; a price change is outside this release. Demonstrate a short capture-to-context success and disclose manual connector setup rather than oversell automation.
4. **Blind spots:** the founder's successful account is not evidence for fresh accounts, signed-out states or accessibility privacy. Device-bound account tokens, stale MCP processes and hidden-sheet semantics can differ. Preserve diagnostics, account-change handling and independent accessibility checks. Do not hide an unresolved gate behind a passing build.
5. **Lessons:** (a) use production-signed exact builds for acceptance; (b) trace a real capture end to end; (c) separate transfer from assistant behavior; (d) keep optional-cloud claims consistent across public and local copy; (e) report unknown privacy/release states honestly.

## Release decisions still pending evidence

Mac can progress independently if its current build, metadata and review gates pass. Capture must not be declared ready while the exact-build and concealed-content checks remain unresolved. Version/build selection follows live ASC inventory. Publishing authorization does not turn a known unresolved gate into a pass. Record actual upload, build selection, review submission and public release separately, with timestamps and receipts; App Store review completion is external and cannot be promised.

## Current submission preparation and automation limits

Mac 1.5.1 draft exists, with optional-iCloud description, release notes and review instructions saved. Six existing demo screenshots were visually inspected; source comparison from screenshot checkpoint d84990f to candidate087cb0a supports retaining their unchanged screens. Screenshot07 AI Tools is stale because the sync card was added, and still needs removal from this draft. Build13 is available but not selected. Fresh snapshots confirm both remain outstanding. Automatic approval review rejected the offscreen screenshot/build controls as unidentified; no indirect retry or review submission was performed. Founder manual remove07/select13/Save was requested.

Capture visible TestFlight inventory shows builds7–9; automatic approval review also rejected expanding Build Uploads despite a fresh visible label. Pending/failed uploads remain unknown, so build10 has not been claimed unused or applied. Founder manual inventory check requested. Independent Inspector test was reopened on the disposable synthetic Duo, not the personal simulator; selecting the fixture process alone is not a completed traversal.

App Privacy reasoning: [Apple's current guidance](https://developer.apple.com/app-store/app-privacy-details/) distinguishes developer/partner collection from data Apple collects through its frameworks. Current source uses user-account CloudDocuments and a CloudKit identity request, not a developer-operated note backend. Retaining Data Not Collected is consistent with that observed architecture; this is an inference, not a blanket exemption for every cloud service or permission to ignore future telemetry changes.

## Draft Capture submission copy — not yet published

Suggested What's New for 1.3, subject to candidate acceptance:

> Optional iCloud sync keeps note text, transcribed captures, to-dos and project summaries available across your devices using the same Apple account. Recordings and repository files stay local. Browse your projects with the updated project cards and continue using Capture on its own when sync is off.

Suggested reviewer notes:

> No separate Unli Rice account is required. Audio capture and transcription run on device; Apple's system may download speech language assets. Optional sync is enabled explicitly in Settings and requires a signed-in Apple account. Sync transfers note text, transcripts, tags, to-dos and project summaries, not audio or repository files. The app explains any account/environment mismatch; it does not reset notes automatically. To verify cross-device transfer, enable the same private iCloud connection in Unli Rice on Mac, record a short non-sensitive capture, save its transcription, and check receipt on Mac. AI-tool configuration is optional and manual. The public policy is https://github.com/CalixOscar/unli-rice/blob/main/PRIVACY.md.

These paragraphs are reviewable local drafts only. No new screenshots, exact Capture candidate acceptance or public review submission is implied.


## Updated receipt — 2026-11-03 00:35 UTC

Earlier automation/manual dependencies above are historical. Fresh browser pixel/label checks resolved Capture upload-history access; all entries4–9 were Complete, no10+. Mac draft now has six screenshots01–06, no07, and build1.5.1(13). Manual release saved, Submit for Review completed, live Waiting for Review and 1 Item Submitted confirmed. Submission: https://appstoreconnect.apple.com/apps/6792837485/distribution/reviewsubmissions/details/c4639080-2dd9-49d8-9bcc-de4d0a68220d . No public release yet.

Capture1.3(10) archive prepared from current source by counter-only edit, root reviewed. Root deep/strict signature and app/widget version audit passed; appProduction configuration confirmed. This archive is development signed (task-allow true), requiring managed distribution signing. Organizer Validate succeeded and Upload for App Store Connect is in progress; completion/processing/eligibility remain to verify. Exact physical candidate and outstanding scoped accessibility acceptance remain. No private user data installed/exported.


### Capture review submission — 2026-11-03 00:48 UTC

Founder explicitly requested “get 1.3 10 submit for review”. Live ASC verified build1.3(10) processed and eligible, selected/saved in the1.3 draft. Manual release was reselected and confirmed by both labeled state and screenshot; the separate phased-update “all users immediately” choice does not select automatic App Store version release. Initial automatic approval review rejected that ambiguity; the manual-selection check resolved it through the requested safer action, then Add for Review and Submit for Review completed. Live Waiting for Review, Draft Submissions(0), and1 Item Submitted confirmed. Submission ac00454a-409f-4e70-83d0-d0810793da7a; build84ef2fbb-ca76-45ed-ad81-591018d68369. Mac1.5.1(13) independently rechecked Waiting for Review, manual release. Neither update is publicly released. Earlier physical/complete accessibility acceptance is not claimed passed; retain the manual release hold and existing acceptance item. No new source or test changes in this submission step.
