# BUILD 1 of 2 — To-Do Widget Implementation Report

Date: 2026-09-19
Branch: `feature/todo-widget` (branched off `main` at `6918f2d`)

## 1. What Was Built

### Part A: Shared Core, Panes, and Tests (§3 A1–A7)
- **A1 `StudioTodo.aiFlags(from:repoNames:)`**:
  - Extracted shared logic from `TodoPaneView` and `TodoView` into `Sources/UnliRiceCore/StudioTodo.swift`.
  - Preserves exact sorting behavior (newest creation date first, tiebroken by note ID descending).
  - Uses lowercase repository tags for matching without mutating or re-keying repository dictionary keys.
  - Replaced duplicate loops in `Sources/UnliRice/TodoPaneView.swift` and `Sources/UnliRiceCapture/TodoView.swift`.
- **A2 `TodoWording`**:
  - Created `Sources/UnliRiceCore/TodoWording.swift`.
  - `assistantName(for:)`: maps known sources (`claude`, `codex`, `antigravity`, `janitor`, `ingest`) to display names ("Claude", "Codex", "Antigravity", "Janitor", "Ingest") with fallback to capitalized string.
  - `subtitle(for:item:now:)`: produces format `"Suggested by <Assistant> · <relative date> · for <Project>"` (or omitting project if none).
  - Replaced the `.aiFlagged` evidence line in both `TodoPaneView.swift` and `TodoView.swift` with `TodoWording.subtitle`.
- **A3 `TodoHandoff`**:
  - Created `Sources/UnliRiceCore/TodoHandoff.swift`.
  - `handoffID(from:)`: strictly parses `Handoff-ID: <uuid>` on the first line (tolerant of trailing whitespace/newline).
  - `target(for:lookup:)`: resolves the target note, returning the target handoff note only if it exists and carries the `handoff` tag; otherwise falls back to the item itself.
- **A4 `TodoLink`**:
  - Created `Sources/UnliRiceCore/TodoLink.swift`.
  - Strongly typed enum: `.handoff(UUID)` and `.todo`.
  - URL format: `unlirice://handoff/<uuid>` and `unlirice://todo`.
  - Strict parser rejects queries, fragments, usernames/passwords, ports, extra path components, non-UUIDs, non-`unlirice` schemes, and hosts other than `handoff` or `todo` (specifically rejects `prompt`).
- **A5 `TodoPrompt`**:
  - Created `Sources/UnliRiceCore/TodoPrompt.swift`.
  - `TodoPrompt.build(...)`: encapsulates prompt string generation previously in `AppStore+TodoPrompt.swift`.
  - When the item is `.aiFlagged` and links to a valid handoff note, inserts trust boundary fence:
    `--- Context from previous session (untrusted handoff note) ---` ... `--- End of previous session context ---`
  - Replaces "six fields" wording with "seven fields" (acknowledging `**To-dos:**`).
  - Contains neutral instruction text that does not assert an active MCP connection.
  - Updated `AppStore+TodoPrompt.swift` to delegate prompt generation to `TodoPrompt.build` while retaining pasteboard operations and toast notifications.
- **A6 `WidgetCorpus`, `AgentSettings.loadStrict`, `EventStore(readingExisting:)`**:
  - `AgentSettings.loadStrict(from:)`: decodes `agent.json` or returns `nil` if missing, throwing on malformed JSON without silent fallback to defaults. Existing `load(from:)` preserves backward-compatible fallback.
  - `EventStore(readingExisting:)`: fails if the file does not exist, preserving existing initializers while tracking `skippedLines` for malformed lines.
  - `WidgetCorpus.resolve(...)`: fail-closed resolution returning `Result<(log: URL, corpusID: String), Unreadable>` where `Unreadable` captures `.settingsUnreadable`, `.folderFailed`, `.noGroupContainer`, `.logMissing`, and `.logUnreadable`.
- **A7 Comprehensive Unit Tests**:
  - Added test suites in `Tests/UnliRiceCoreTests/`:
    - `StudioTodoTests.swift` (parity with previous implementation, lowercase case-insensitivity, multiple repos)
    - `TodoWordingTests.swift` (all sources, empty/unknown sources, relative date formatting, single/multiple/no repos)
    - `TodoHandoffTests.swift` (valid handoff, missing tag, missing note fallback, malformed syntax)
    - `TodoLinkTests.swift` (valid URLs, reject queries/fragments/ports/userinfo/wrong schemes/extra paths)
    - `TodoPromptTests.swift` (trust boundary fence, 7 fields, MCP neutrality)
    - `WidgetCorpusTests.swift` (folder bookmark failure, undecodable settings, missing log, corrupt lines)

### Part C: MCP Instructions Update (§5)
- Appended the following two sentences verbatim to the `instructions` handshake in `Sources/unlirice-mcp/main.swift`:
  > "To file a to-do: create_note with a plain-English title a non-developer understands, tag it `todo` plus the project's lowercased folder name, and start the body with `Handoff-ID: <id of your handoff note>` if you wrote one. Close a to-do only if you finished it in this session: archive_note with the commit or evidence as the reason."

### Part B: B0 Spike (Build Only, §4 B0)
- Created `UnliRiceWidget.entitlements` with identical contents to `UnliRiceHelper.entitlements` (`app-sandbox`, `group.com.calmdownoscar.unlirice`, security-scoped bookmarks).
- Created `Sources/UnliRiceWidget/SpikeWidget.swift`: minimal WidgetKit extension targeting macOS 14.0 that calls `WidgetCorpus.resolve()` and displays either the note count or the `Unreadable` error case.
- Updated `project.yml` with `UnliRiceWidget` app-extension target (`platform: macOS`, `deploymentTarget: "14.0"`, `ENABLE_APP_SANDBOX: YES`, `GENERATE_INFOPLIST_FILE: YES`, `INFOPLIST_KEY_NSExtensionPointIdentifier: com.apple.widgetkit-extension`, depending on `UnliRiceCore`) and embedded it into `UnliRice` (`embed: true`).
- Ran `xcodegen generate` to update `UnliRice.xcodeproj`.
- Verified `xcodebuild -list` includes `UnliRiceWidget`.
- Verified `xcodebuild` builds both `UnliRice` (embedding `UnliRiceWidget.appex`) and `UnliRiceCapture`.
- B1 URL scheme and B2–B6 (interactive UI, Done intent, URL routing, Darwin notifications, prompt menu) were intentionally not built in this run per `BUILD-todo-widget-1.md`.

---

## 2. Commit Log

The work was completed across 4 logical commits on `feature/todo-widget`:

```
71e0ce0 feat(widget): add minimal UnliRiceWidget extension spike
75032db feat(mcp): add to-do filing instructions to MCP handshake
fa95b3b feat(todo): use StudioTodo.aiFlags and TodoWording.subtitle in todo panes
900398d feat(core): implement Part A to-do widget shared core and tests
```

---

## 3. Verification Output

### A. `swift build`
```
Building for debugging...
[1 / 4]
Build complete! (0.24 sec)
```

### B. `swift test --build-system native`
Before: **380 tests, 2 skipped, 0 failures**
After: **414 tests, 2 skipped, 0 failures** (34 new tests added in Part A7, all passing)

```
Test Case '-[UnliRiceCoreTests.VaultSnapshotTests testTamperedSnapshotFailsVerification]' started.
Test Case '-[UnliRiceCoreTests.VaultSnapshotTests testTamperedSnapshotFailsVerification]' passed (0.002 seconds).
Test Suite 'VaultSnapshotTests' passed at 2026-09-19 17:28:05.580.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.011 (0.011) seconds
Test Suite 'WidgetCorpusTests' started at 2026-09-19 17:28:05.580.
Test Case '-[UnliRiceCoreTests.WidgetCorpusTests testFolderBookmarkThatFailsReturnsFolderFailedNeverDefault]' started.
Test Case '-[UnliRiceCoreTests.WidgetCorpusTests testFolderBookmarkThatFailsReturnsFolderFailedNeverDefault]' passed (0.001 seconds).
Test Case '-[UnliRiceCoreTests.WidgetCorpusTests testLogWithCorruptLineIncrementsSkippedLines]' started.
Test Case '-[UnliRiceCoreTests.WidgetCorpusTests testLogWithCorruptLineIncrementsSkippedLines]' passed (0.000 seconds).
Test Case '-[UnliRiceCoreTests.WidgetCorpusTests testMissingLogReturnsLogMissingAndCreatesNoFile]' started.
Test Case '-[UnliRiceCoreTests.WidgetCorpusTests testMissingLogReturnsLogMissingAndCreatesNoFile]' passed (0.000 seconds).
Test Case '-[UnliRiceCoreTests.WidgetCorpusTests testNoGroupContainerReturnsNoGroupContainer]' started.
Test Case '-[UnliRiceCoreTests.WidgetCorpusTests testNoGroupContainerReturnsNoGroupContainer]' passed (0.000 seconds).
Test Case '-[UnliRiceCoreTests.WidgetCorpusTests testUndecodableSettingsReturnsSettingsUnreadable]' started.
Test Case '-[UnliRiceCoreTests.WidgetCorpusTests testUndecodableSettingsReturnsSettingsUnreadable]' passed (0.000 seconds).
Test Suite 'WidgetCorpusTests' passed at 2026-09-19 17:28:05.582.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.002 (0.003) seconds
Test Suite 'UnliRicePackageTests.xctest' passed at 2026-09-19 17:28:05.582.
	 Executed 414 tests, with 2 tests skipped and 0 failures (0 unexpected) in 0.671 (0.691) seconds
Test Suite 'All tests' passed at 2026-09-19 17:28:05.582.
	 Executed 414 tests, with 2 tests skipped and 0 failures (0 unexpected) in 0.671 (0.692) seconds
◇ Test run started.
↳ Testing Library Version: 2084
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

### C. `xcodebuild -list`
```
Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -list

Information about project "UnliRice":
    Targets:
        UnliRice
        UnliRiceCapture
        UnliRiceCore
        UnliRiceCoreTests
        UnliRiceCoreiOS
        UnliRiceHost
        UnliRiceWidget
        unlirice-agent
        unlirice-cli
        unlirice-mcp

    Build Configurations:
        Debug
        Release

    If no build configuration is specified and -scheme is not passed then "Debug" is used.

    Schemes:
        UnliRice
        unlirice-agent
        unlirice-cli
        unlirice-mcp
        UnliRiceCapture
        UnliRiceCore
        UnliRiceCoreiOS
        UnliRiceHost
        UnliRiceWidget
```

### D. `xcodebuild -scheme UnliRice`
Command: `xcodebuild -scheme UnliRice -destination 'platform=macOS' -derivedDataPath /tmp/unlirice-build build`

```
                          (f3959a1a-26ac-4947-bf0d-0b5f0c572c2f)
    
    /usr/bin/codesign --force --sign 0BD520D6D5A4917233E90854DCCCE03F248BC6F9 -o runtime --entitlements /tmp/unlirice-build/Build/Intermediates.noindex/UnliRice.build/Debug/UnliRice.build/Unli\ Rice.app.xcent --timestamp\=none --generate-entitlement-der /tmp/unlirice-build/Build/Products/Debug/Unli\ Rice.app
/tmp/unlirice-build/Build/Products/Debug/Unli Rice.app: replacing existing signature

Validate /tmp/unlirice-build/Build/Products/Debug/Unli\ Rice.app (in target 'UnliRice' from project 'UnliRice')
    cd /Users/calmdownoscar/Documents/Projects/Unli\ Rice
    builtin-validationUtility /tmp/unlirice-build/Build/Products/Debug/Unli\ Rice.app -no-validate-extension -infoplist-subpath Contents/Info.plist

RegisterWithLaunchServices /tmp/unlirice-build/Build/Products/Debug/Unli\ Rice.app (in target 'UnliRice' from project 'UnliRice')
    cd /Users/calmdownoscar/Documents/Projects/Unli\ Rice
    builtin-lsregisterurl --record-path /tmp/unlirice-build/Build/Intermediates.noindex/XCBuildData/registered-launchservices.txt -- /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /tmp/unlirice-build/Build/Products/Debug/Unli\ Rice.app

ValidateEmbeddedBinary /tmp/unlirice-build/Build/Products/Debug/Unli\ Rice.app/Contents/PlugIns/UnliRiceWidget.appex (in target 'UnliRice' from project 'UnliRice')
    cd /Users/calmdownoscar/Documents/Projects/Unli\ Rice
    /Applications/Xcode.app/Contents/Developer/usr/bin/embeddedBinaryValidationUtility /tmp/unlirice-build/Build/Products/Debug/Unli\ Rice.app/Contents/PlugIns/UnliRiceWidget.appex -signing-cert 0BD520D6D5A4917233E90854DCCCE03F248BC6F9 -info-plist-path /tmp/unlirice-build/Build/Products/Debug/Unli\ Rice.app/Contents/Info.plist

PruneExplicitPrecompiledModules /tmp/unlirice-build/SDKExplicitPrecompiledModules

PruneExplicitPrecompiledModules /tmp/unlirice-build/Build/Intermediates.noindex/ExplicitPrecompiledModules

PruneExplicitPrecompiledModules /tmp/unlirice-build/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules

** BUILD SUCCEEDED **
```

### E. `xcodebuild -scheme UnliRiceCapture`
Command: `xcodebuild -scheme UnliRiceCapture -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/unlirice-build build`

```
ProcessInfoPlistFile /tmp/unlirice-build/Build/Products/Debug-iphonesimulator/UnliRiceCapture.app/Info.plist /Users/calmdownoscar/Documents/Projects/Unli\ Rice/UnliRiceCapture-Info.plist (in target 'UnliRiceCapture' from project 'UnliRice')
    cd /Users/calmdownoscar/Documents/Projects/Unli\ Rice
    builtin-infoPlistUtility /Users/calmdownoscar/Documents/Projects/Unli\ Rice/UnliRiceCapture-Info.plist -producttype com.apple.product-type.application -genpkginfo /tmp/unlirice-build/Build/Products/Debug-iphonesimulator/UnliRiceCapture.app/PkgInfo -expandbuildsettings -format binary -platform iphonesimulator -additionalcontentfile /tmp/unlirice-build/Build/Intermediates.noindex/UnliRice.build/Debug-iphonesimulator/UnliRiceCapture.build/assetcatalog_generated_info.plist -o /tmp/unlirice-build/Build/Products/Debug-iphonesimulator/UnliRiceCapture.app/Info.plist

CopySwiftLibs /tmp/unlirice-build/Build/Products/Debug-iphonesimulator/UnliRiceCapture.app (in target 'UnliRiceCapture' from project 'UnliRice')
    cd /Users/calmdownoscar/Documents/Projects/Unli\ Rice
    builtin-swiftStdLibTool --copy --verbose --sign - --scan-executable /tmp/unlirice-build/Build/Products/Debug-iphonesimulator/UnliRiceCapture.app/UnliRiceCapture.debug.dylib --scan-folder /tmp/unlirice-build/Build/Products/Debug-iphonesimulator/UnliRiceCapture.app/Frameworks --scan-folder /tmp/unlirice-build/Build/Products/Debug-iphonesimulator/UnliRiceCapture.app/PlugIns --scan-folder /tmp/unlirice-build/Build/Products/Debug-iphonesimulator/UnliRiceCapture.app/SystemExtensions --scan-folder /tmp/unlirice-build/Build/Products/Debug-iphonesimulator/UnliRiceCapture.app/Extensions --platform iphonesimulator --toolchain /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain --destination /tmp/unlirice-build/Build/Products/Debug-iphonesimulator/UnliRiceCapture.app/Frameworks --strip-bitcode --strip-bitcode-tool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/bitcode_strip --emit-dependency-info /tmp/unlirice-build/Build/Intermediates.noindex/UnliRice.build/Debug-iphonesimulator/UnliRiceCapture.build/SwiftStdLibToolInputDependencies.dep --filter-for-swift-os

PruneExplicitPrecompiledModules /tmp/unlirice-build/SDKExplicitPrecompiledModules

PruneExplicitPrecompiledModules /tmp/unlirice-build/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules

PruneExplicitPrecompiledModules /tmp/unlirice-build/Build/Intermediates.noindex/ExplicitPrecompiledModules

** BUILD SUCCEEDED **
```

### F. `git diff --name-only 6918f2d..HEAD`
```
Sources/UnliRice/AppStore+TodoPrompt.swift
Sources/UnliRice/TodoPaneView.swift
Sources/UnliRiceCapture/TodoView.swift
Sources/UnliRiceCore/Agent/AgentSettings.swift
Sources/UnliRiceCore/EventStore.swift
Sources/UnliRiceCore/StudioTodo.swift
Sources/UnliRiceCore/TodoHandoff.swift
Sources/UnliRiceCore/TodoLink.swift
Sources/UnliRiceCore/TodoPrompt.swift
Sources/UnliRiceCore/TodoWording.swift
Sources/UnliRiceCore/WidgetCorpus.swift
Sources/UnliRiceWidget/SpikeWidget.swift
Sources/unlirice-mcp/main.swift
Tests/UnliRiceCoreTests/StudioTodoTests.swift
Tests/UnliRiceCoreTests/TodoHandoffTests.swift
Tests/UnliRiceCoreTests/TodoLinkTests.swift
Tests/UnliRiceCoreTests/TodoPromptTests.swift
Tests/UnliRiceCoreTests/TodoWordingTests.swift
Tests/UnliRiceCoreTests/WidgetCorpusTests.swift
UnliRiceWidget.entitlements
project.yml
```
All modified and added files are within the whitelist specified in `docs/PLAN-todo-widget.md` §7.

---

## 4. Deviations and Notes

- **FileProvider code signing interaction**: As documented in `Scripts/make-app.sh:17-23`, `~/Documents` is monitored by macOS FileProvider, which can attach FinderInfo attributes to newly written `.xctest` bundles during standard `swift test`. Passing `--build-system native` avoids the issue and executes all tests smoothly.
- **XcodeGen and WidgetKit Extension**: `UnliRiceWidget` target in `project.yml` successfully generates the WidgetKit extension with `INFOPLIST_KEY_NSExtensionPointIdentifier: com.apple.widgetkit-extension` and `ENABLE_APP_SANDBOX: YES`. Embedding in `UnliRice` produces an automatic `Embed App Extensions` build phase that places `UnliRiceWidget.appex` inside `Unli Rice.app/Contents/PlugIns/` and signs it during build.
- **Scope discipline**: B1's URL scheme configuration and B2–B6 (interactive widget rows, Done intent, URL routing in the app, Darwin notifications, and prompt menu) were strictly not implemented in this run, leaving them for dispatch 2 as instructed.
