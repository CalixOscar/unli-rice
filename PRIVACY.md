# Unli Rice Privacy Policy

Effective July 21, 2026.

Unli Rice is a local-first macOS app. It has no account, analytics,
advertising, tracking, purchases, or developer-operated server. Notes and app
settings stay on the user's Mac; calmdownoscar does not receive them.

## Files the user chooses

Unli Rice reads or writes outside its own sandbox container only after the user
selects a folder in the macOS file picker. The app stores a security-scoped
bookmark so a selected folder remains available for scheduled work. Claude
session access can be removed in Automation, and the note store can be changed
in Connect.

## AI tools

When the user manually configures an AI tool to use the bundled Unli Rice MCP
helper, that tool can read and write the user's notes. That tool operates under
its own privacy terms. Unli Rice does not read or modify another app's
configuration.

## Optional local embeddings

If the user configures a local embedding server, Unli Rice sends note titles
only to a loopback address on the same Mac. The app rejects non-local server
addresses.

## iOS Companion App (Unli Rice Capture)

Unli Rice Capture is an on-device voice capture app for iOS. Audio recordings are transcribed locally on device using Apple's native SpeechAnalyzer framework; audio data is never uploaded to calmdownoscar or any third party.

- **Data collection**: No account, analytics, advertising, tracking, or developer server.
- **Network activity**: The only network request is Apple's system-level download of on-device speech recognition language models (`AssetInventory`) when first required by iOS.
- **Sync**: Optional shared folder synchronization is performed strictly through the user's selected iCloud Drive folder using security-scoped bookmarks.

## Retention and deletion

Notes remain in the store controlled by the user until the user archives and
permanently removes them from Trash. Removing the app does not delete a store
the user placed in another folder. Notes can be exported at any time.

For app support, privacy questions, or deletion help, use the public support
tracker at <https://github.com/CalixOscar/unli-rice/issues>. Do not include
private note content in a public issue.
