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

## Promotional text (2026-10-31, for 1.5)

170 characters max; can be changed at any time without a new review.

```text
New in 1.5: Studio shows each project's branches, notes and next step at a glance. Your AI tools share one set of notes on your Mac. Free, open source, no account.
```

## App Store description (2026-10-31, for 1.5)

Kept here so it's versioned with the rest of the submission, not only pasted
into App Store Connect. Update this section whenever the description changes;
regenerate it after any feature that changes the sidebar or a headline
capability (House Rules, Needs You, Trust Center and the Extras list are all named
below and drift if renamed).

```
Unli Rice gives the AI tools you use one place on your Mac for what they should know and the rules they should follow. Connect Claude, ChatGPT, Codex, Cursor or your own local tools over MCP so they read and write the same notes, instead of you re-explaining yourself to every new session.

STUDIO: WHERE YOUR PROJECTS STAND
Pick the folders that hold your projects and Studio shows them as a stack of cards: which ones need you, their branches, the notes that belong to each, and how far each plan has come from idea to post-mortem. Copy prompt hands your AI tool the next step.

GROUNDING: WHAT YOUR AI KNOWS
Notes holds everything your assistants and you have written, each change attributed and dated. The folder your AI can read keeps a plain-Markdown copy for tools that can't use MCP. Details shows whether memory is working and which assistant last checked in.

GUARDRAILS: WHAT YOUR AI SHOULD ALWAYS DO
House Rules are your standing instructions, saved as a note your assistants find when they check your notes at the start of a session: what to read first, what's worth remembering, how to attribute their work, and when to stop and ask you. Start from a built-in template, including Engineering Guardrails for coding assistants, or import your own. Need you collects only what's waiting on your decision. The Trust Center checks that your memory is readable and writable, shows which assistants have connected, and makes verified recovery points before big changes.

A PERMANENT, ATTRIBUTED RECORD
Every change is an append-only event. Connected assistants can append and create; they cannot rewrite history or permanently delete anything. Archiving is reversible.

EXTRAS, WHEN YOU WANT THEM
The gear menu holds Setup, the Trust Center and archived notes. Setup › Extras turns on To do, the note Map, Your year so far, separate memories, PDF and ZIP export and more. Each is off until you turn it on, and turning one off never deletes anything.

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

### App Review Notes Copy-Paste Text for App Store Connect (1.5)

```text
No demo account is needed — Unli Rice has no sign-in or account system.

Unli Rice 1.5 replaces the sidebar with two tabs, Studio and Guardrails & Grounding, and a gear menu at the top right. Nothing is removed from the app.

Unli Rice works on its own without any AI tool or account. To try it without an MCP client:
1. Open Unli Rice.app. On the first screen, click "Use Unli Rice without connecting".
2. Click the Studio tab, then Pick a folder, and choose a folder that contains one or more git repositories. Each repository becomes a card with its branches and notes; the expand button in the deck's corner shows its steps and Copy prompt.
3. Click the Guardrails & Grounding tab, then Open notes. Type a title in the "New note title…" field and some text in the box under it, click Add, then search for the note.
4. Back on the Guardrails & Grounding tab, click Edit beside House Rules, select Engineering Guardrails and click Use as Draft. Setup opens on AI Tools; scroll down to House Rules and click Save to notes.
5. Click the gear, then Trust Center, then Run checks.
6. Click the gear, then Setup, then Extras, and turn on Map; Map appears in the gear menu.

To try the optional MCP helper (/Applications/Unli Rice.app/Contents/MacOS/unlirice-mcp), add this to an MCP client such as Claude Desktop, restart the client, and ask it to save a note in Unli Rice:
{
  "mcpServers": {
    "unlirice": {
      "command": "/Applications/Unli Rice.app/Contents/MacOS/unlirice-mcp",
      "args": []
    }
  }
}

Reviewer guide with step-by-step instructions and sample configs:
https://github.com/CalixOscar/unli-rice/blob/main/docs/APPLE_REVIEW_GUIDE.md

The app stores data in its App Group container, reads other folders only after the user picks them in an open panel, never edits another app's configuration files (Connect only copies text), and the optional embedding connection accepts localhost only. The China mainland storefront remains deselected.
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
