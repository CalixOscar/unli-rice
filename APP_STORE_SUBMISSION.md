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

## App Store description (2026-07-24)

Kept here so it's versioned with the rest of the submission, not only pasted
into App Store Connect. Update this section whenever the description changes;
regenerate it after any feature that changes the sidebar or a headline
capability (Brain Map, Profiles, House Rules, Trust Center are all named
below and drift if renamed).

```
Unli Rice gives every AI tool you use a shared, permanent memory on your Mac. Connect Claude, ChatGPT, Gemini, coding agents, or your own local tools over MCP so they read and write into the same notes — instead of you re-explaining yourself to a new session every time.

WHAT'S DOING WHAT
Home shows what's happening right now. Needs You collects everything actually waiting on a decision — nothing else. Brain Map visualizes your notes as a living graph: select any note to see exactly what it's connected to, or watch Grow replay your memory being built, oldest note first.

A PERMANENT, ATTRIBUTED RECORD
Every change is an immutable, append-only event. You can see who wrote or updated a note, what happened, and when. Connected agents can append and create — they cannot rewrite history or permanently delete anything.

PROFILES, YOUR WAY
Build a personal AI Context Profile — identity, voice, principles, guardrails — with the Profile Builder, or start from a template (Studio Standard, Solo Developer, Writer/Researcher, Minimalist). Run multiple Profiles as separate vaults, each with its own Master Profile guardrails. Mirror Export generates a plain-markdown copy of any Profile for AI tools that can't use MCP.

HOUSE RULES, PER MEMORY SPACE
Each memory space can carry its own House Rules — standing instructions telling connected agents what to read first, what's worth remembering, how to attribute their work, and when a conflict should wait for you. Start from a built-in template or import your own Markdown, and every saved revision joins the same auditable history as everything else.

TRUST, VERIFIABLE
The Trust Center's Connection Doctor checks whether your memory space is readable and writable, whether an assistant has actually connected, whether recovery points exist, and whether background routines are running. Diagnostics record only client names, versions, and outcomes — never note contents. Create verified local recovery points before big changes; restores are conservative and never touch your current history.

STAYS OUT OF YOUR WAY
Turn on "Keep working with the window closed" and ingestion and maintenance can continue in the background. Anything that needs a human decision waits quietly for you. Looking Back can read a month or a year of notes back to you, curated from the memory you've already built.

Nothing running unattended can exceed the app's own limits: background routines may only tag and flag, ingestion may only create and append, recovery requires a deliberate action from you, and every structural question is yours to answer.

Unli Rice runs entirely on your Mac. No account, no analytics, no cloud sync, no bundled model — the reasoning comes from whichever AI tool you connect, and the optional embedding connection is restricted to localhost.

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
   - Unli Rice is a standalone native macOS note vault app that does not require an external AI tool or subscription to function. All features (Notes, Profile Builder, House Rules, Brain Map, Mirror Export, Trust Center) are 100% usable directly within the standalone GUI.
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
