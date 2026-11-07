# Capture accessibility observations — 2026-11-03

This is an observation summary, not a raw accessibility-tree artifact. The full
trees were emitted in the Codex computer-use tool transcript with
`hub.getAXState({disableDiffing:true})`; they were not saved as separate files.

The target was the disposable **Unli Rice Production QA Duo** simulator
`58723D30-EF7E-45FB-A2A5-3AF1E3DCD9E1`, iOS 27.2, running the already-installed
synthetic fixture `com.calmdownoscar.unlirice.productionqa` with
`--qa-diagnostic`. The fixture uses synthetic temporary data. Device Hub exposed
the simulated app's accessibility tree through CUA; its QA controls changed the
fixture presentation state. This is independent of the XCTest element queries,
but it does not establish a complete VoiceOver traversal or physical-device result.

## Observed cases

- **Typed note:** The open sheet exposed a settable Group with value `Synthetic
  privacy sentinel`. After QA Close, the full tree contained `Project: Unli
  Thoughts`, `Record`, and `Tap mic to record a thought`, with no editor, marker,
  or keyboard. QA Open restored the same Group value. QA Lock then exposed `Lock`,
  `Unli Rice is locked`, and `Unlock with Touch ID`, with no editor or marker.
  One fold/reopen was observed in this independent tree check.
- **To-do note:** The open sheet exposed a settable Group with value `Synthetic
  todo sentinel`. QA Close showed the recorder subtree and no editor, marker, or
  keyboard; QA Open restored the same value. A later fresh fixture repeated one
  fold and reopened with the marker intact; its second fold was not completed.
  QA Lock in the earlier run presented the system passcode prompt. No passcode was
  entered, and the app's locked cover was not independently observed for this case.
- **Settings:** The open tree exposed `Capture Settings`, `Archived Notes`, and
  `Sync with iCloud`. Two QA Close cycles each exposed the recorder subtree without
  those settings controls; the intervening QA Open restored them.

These observations supplement the existing simulator and XCTest evidence in
`PLAN-production-studio.md`; they do not replace its three failing strict concealed
editor queries, establish all sheet variants, or close B2/P5. No production source
or privacy assertion was changed during this check.
