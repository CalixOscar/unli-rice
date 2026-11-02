# Production Studio release readiness — 2026-11-03

Scope: existing Unli Rice macOS and Unli Rice Capture iOS releases, not the separate open-source workspace proposal. Founder explicitly requested returning to publishing both apps with new iCloud settings. This record is a bounded prelaunch assessment, not a claim that either public update has been submitted.

## Evidence and remaining gates

- Mac 1.5.1 (13) uploaded, processed, installed via TestFlight; actual original capture receipt and explicit approved connection migration are recorded at aa91d60. Fresh installed MCP worked without binding error; an old registered process required reconnect. Live ASC recheck on this resumed pass shows Ready to Submit.
- No `Sources/` or `project.yml` drift from Mac archive checkpoint 087cb0a through 724638b (read-only git diff, this pass). Prior signature, production entitlement, universal architecture and test results remain in the production plan; they were not rerun here.
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
