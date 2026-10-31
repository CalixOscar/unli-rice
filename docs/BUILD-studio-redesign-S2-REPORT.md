# S2 build report — unreviewed

**Base:** 0d83573; branch `codex/studio-S2b`.
**Ground check:** `ProjectGarden.swift:18–44,33,82,144,179,250,364,370,417` match the plan; §2.8 specifies the API, colors and pairs that were missing before.
**Builder:** `model: gpt-reserve`; `reasoning effort: medium` (matches `AGENTS.md`).
**Files:** `Sources/UnliRiceCore/GardenCrate.swift`, `Sources/UnliRiceCore/StudioPalette.swift`, `Tests/UnliRiceCoreTests/GardenCrateTests.swift`, `Tests/UnliRiceCoreTests/StudioPaletteTests.swift`, and this report.
**Builder verification:** `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build`: 480 executed, 0 failures, 2 skipped. Focused GardenCrate, StudioPalette and ProjectGarden tests: 32 executed, 0 failures, 0 skipped (including 23 ProjectGarden tests).
**Driver verification:** same full-suite command: 480 executed, 0 failures, 2 skipped (478 passed). `git diff --check`: pass. Source and test files are the four named in the handoff.
**Stop:** none. Two new source files require `xcodegen generate` before Xcode builds; no Xcode build was run for this core-only step.
