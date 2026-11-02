# Unli Rice Privacy Policy

Effective November 1, 2026 (native iCloud update).

Unli Rice is a local-first macOS app. It has no account, analytics,
advertising, tracking, purchases, or developer-operated server. Notes and app
settings are stored locally by default; calmdownoscar does not receive them.
Optional iCloud sync uses the user's Apple account and Apple's services.

## Files the user chooses

Apart from optional iCloud sync, Unli Rice reads or writes outside its own sandbox
container only after the user selects a folder in the macOS file picker. The app stores a security-scoped
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
- **Network activity**: Apple may download on-device speech recognition language models when required. If the user enables sync, Apple also transfers the selected sync data between devices.
- **Sync**: The same optional native iCloud sync described below is available on iOS. A manually selected shared folder remains an advanced alternative.

## Optional iCloud sync

Sync is off until the user enables it. It transfers existing and future note
text, transcribed captures, tags, to-dos and project summaries through an
app-managed iCloud space to devices using the same Apple account. Notes can
contain file paths and other information the user saved; project summaries can
include repository names, branch information and the Mac's observed status.
Audio recordings and repository source files are not part of this sync.

The bundled MCP helper can receive and publish note changes independently while
an AI client is running. Project summaries update while the Mac app is running
and can access the project folders the user has granted.

Turning sync off stops new transfers by that app. It does not erase copies
already delivered to other devices or iCloud. Account changes pause access;
existing notes stay on the device. calmdownoscar does not operate the sync server
or receive its contents.

## Retention and deletion

Archiving hides a note reversibly. A store that has been linked to native iCloud
uses archive only, including after sync is turned off; permanent removal from its
event history is unavailable. A store never linked to native iCloud retains its
existing Trash and backup controls. Removing the app does not delete a store
the user placed in another folder. Notes can be exported at any time.

For app support, privacy questions, or deletion help, use the public support
tracker at <https://github.com/CalixOscar/unli-rice/issues>. Do not include
private note content in a public issue.
