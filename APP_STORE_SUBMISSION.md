# Mac App Store submission

The code target is prepared for a free Mac App Store release. The remaining
items require the owner's Apple Developer and App Store Connect accounts.

## Identifiers and signing

1. Register the App ID `com.calmdownoscar.unlirice`.
2. Register the App Group `group.com.calmdownoscar.unlirice` and attach it to
   the app identifier.
3. The team (`22SNGN5JYD`) and automatic signing are persisted in `project.yml`
   for the app and both helper targets. Confirm Xcode resolves every target.
4. Keep the app sandbox, user-selected read/write files, app-scoped bookmarks,
   App Group, and outgoing network entitlements. Do not add temporary exception
   entitlements.

`project.yml` is the source of truth for the generated Xcode project. The
`.xcodeproj` is intentionally ignored; after editing the spec, run
`xcodegen generate` again before building or archiving.

## App Store Connect

- Price: **Free**. There are no in-app purchases or subscriptions.
- Category: Productivity.
- Privacy label: **Data Not Collected**. Notes stay on-device; the optional
  embedding endpoint is restricted to localhost.
- Privacy policy URL:
  `https://github.com/CalixOscar/unli-rice/blob/main/PRIVACY.md`.
- Support URL: `https://github.com/CalixOscar/unli-rice/issues`.
- Marketing/about URL: `https://calmdownoscar.com/apps` — lists Unli Rice and
  links to the GitHub repo. `calmdownoscar.com/unlirice` does not exist
  (404); do not use it in any App Store Connect field.
- Supply screenshots, description, keywords, age rating, and copyright.
- Encryption: the app does not implement non-exempt encryption;
  `ITSAppUsesNonExemptEncryption` is `false`.

## App Store description (2026-10-29, for 1.4)

Kept here so it's versioned with the rest of the submission, not only pasted
into App Store Connect. Update this section whenever the description changes;
regenerate it after any feature that changes the sidebar or a headline
capability (Brain Map, Profiles, House Rules, Trust Center are all named
below and drift if renamed).

```
Unli Rice gives the AI tools you use one place on your Mac for what they should know and the rules they should follow. Connect Claude, ChatGPT, Codex, Cursor or your own local tools over MCP so they read and write the same notes, instead of you re-explaining yourself to every new session.

GROUNDING: WHAT YOUR AI KNOWS
Home shows what's happening right now and which assistant last checked in. Notes holds everything your assistants and you have written, each change attributed and dated. The folder your AI can read keeps a plain-Markdown copy for tools that can't use MCP.

GUARDRAILS: WHAT YOUR AI SHOULD ALWAYS DO
House Rules are standing instructions every connected assistant reads at the start of a session: what to read first, what's worth remembering, how to attribute its work, and when to stop and ask you. Start from a built-in template, including Engineering Guardrails for coding assistants, or import your own. Needs You collects only what's waiting on your decision. The Trust Center checks that your memory is readable and writable, shows which assistants have connected, and makes verified recovery points before big changes.

A PERMANENT, ATTRIBUTED RECORD
Every change is an append-only event. Connected assistants can append and create; they cannot rewrite history or permanently delete anything. Archiving is reversible.

EXTRAS, WHEN YOU WANT THEM
Setup › Extras turns on Projects (where each project stands and what comes next), To do, the note Map, Your year so far, separate memories, PDF and ZIP export and more. Each is off until you turn it on, and turning one off never deletes anything.

STAYS OUT OF YOUR WAY
Background work is off unless you turn it on, and each background job has its own switch. Nothing running unattended can exceed the app's own limits: it may only tag and flag, imports may only create and append, and every structural question is yours to answer.

Unli Rice runs entirely on your Mac. No account, no analytics, no cloud sync, no bundled model. The reasoning comes from whichever AI tool you connect, and the optional embedding connection is restricted to localhost.

Unli Rice is open source and MIT licensed.
```

## Review notes

Tell App Review:

- Unli Rice stores notes in its App Group container by default.
- External folders are accessed only after an `NSOpenPanel` selection and are
  retained with security-scoped bookmarks.
- Connect copies a configuration snippet to the clipboard. It never reads or
  modifies Claude, Cursor, Codex, or Antigravity configuration files.
- `unlirice-mcp` is first-party code embedded and independently sandboxed
  inside the app bundle at `/Applications/Unli Rice.app/Contents/MacOS/unlirice-mcp`.
- The optional background helper is registered with `SMAppService` only after
  the user turns on “Keep working with the window closed.”
- The optional embedding server accepts loopback addresses only.
- China mainland storefront availability has been deselected in App Store Connect.

### Sample MCP Client Configurations & Reviewer Guide

Permanently hosted reviewer guide and sample configuration files:
- Reviewer Guide: `https://github.com/CalixOscar/unli-rice/blob/main/docs/APPLE_REVIEW_GUIDE.md`
- Sample JSON Config: `https://raw.githubusercontent.com/CalixOscar/unli-rice/main/docs/sample_configs/claude_desktop_config.json`
- Sample TOML Config: `https://raw.githubusercontent.com/CalixOscar/unli-rice/main/docs/sample_configs/config.toml`

### App Review Notes Copy-Paste Text for App Store Connect

```text
Thank you for your review. We have addressed both guidelines as follows:

1. Guideline 5 (Legal - China Storefront):
   - We have removed the China mainland storefront from our app's Availability settings in App Store Connect. The app is no longer distributed in China mainland.

2. Guideline 2.1(a) (Information Needed - MCP Client Configuration & Verification):
   - Unli Rice is a standalone native macOS note vault app that does not require an external AI tool or subscription to function. All features (Notes, House Rules, Needs You, Trust Center, Mirror Export) are usable directly within the standalone GUI. Optional features (Projects, To do, Map, Your year so far, Separate memories / Profile Builder, PDF and ZIP export) are off by default and can be turned on in Setup › Extras; each switch only shows or hides that feature.
   - For reviewing the optional Model Context Protocol (MCP) inter-process communication helper embedded at `/Applications/Unli Rice.app/Contents/MacOS/unlirice-mcp`, we have published permanently hosted sample configuration files and testing instructions:

   - Comprehensive Reviewer Guide: https://github.com/CalixOscar/unli-rice/blob/main/docs/APPLE_REVIEW_GUIDE.md
   - Sample JSON Config File: https://raw.githubusercontent.com/CalixOscar/unli-rice/main/docs/sample_configs/claude_desktop_config.json
   - Sample TOML Config File: https://raw.githubusercontent.com/CalixOscar/unli-rice/main/docs/sample_configs/config.toml

Sample MCP Client Configuration snippet for `mcpServers`:
{
  "mcpServers": {
    "unlirice": {
      "command": "/Applications/Unli Rice.app/Contents/MacOS/unlirice-mcp",
      "args": []
    }
  }
}

Test steps without an MCP client:
1. Open Unli Rice.app.
2. Go to Setup -> Who You Are & Profiles -> Load Template... -> Studio Standard -> Finish. Note files are created in Notes.
3. Go to Setup -> House Rules -> select Standard Memory -> Save.
4. Go to Notes tab -> click + New Note -> enter title and content -> search for the note.
5. Go to Brain Map tab to view the visual note graph.
```

## Archive and validate

Local release verification on 2026-07-21 passed: 205 Swift tests, Xcode static
analysis, a signed universal Release archive, strict deep code-signature checks,
embedded helper Info.plists and stable identifiers, app icon metadata, and
privacy/property-list validation. The current cached development profile is the
team wildcard profile and does not grant the App Group, so complete identifiers
1–2 above before attempting App Store Connect validation.

1. Increment `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
   `project.yml`, then regenerate the project.
2. In Xcode, choose **Any Mac (Apple Silicon, Intel)** and **Product → Archive**.
3. In Organizer, run **Validate App**, resolve every entitlement or privacy
   warning, then choose **Distribute App → App Store Connect**.
4. Test the exact uploaded build through TestFlight before submitting it for
   review.
