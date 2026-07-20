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
- Supply screenshots, description, keywords, age rating, and copyright.
- Encryption: the app does not implement non-exempt encryption;
  `ITSAppUsesNonExemptEncryption` is `false`.

## Review notes

Tell App Review:

- Unli Rice stores notes in its App Group container by default.
- External folders are accessed only after an `NSOpenPanel` selection and are
  retained with security-scoped bookmarks.
- Connect copies a configuration snippet to the clipboard. It never reads or
  modifies Claude, Cursor, Codex, or Antigravity configuration files.
- `unlirice-mcp` is first-party code embedded and independently sandboxed
  inside the app. It has a stable signed identifier because a compatible AI
  tool launches it directly after the user manually copies the configuration.
- The optional background helper is registered with `SMAppService` only after
  the user turns on “Keep working with the window closed.”
- The optional embedding server accepts loopback addresses only.

Provide a concise test path for Connect, folder selection, export, and the
background toggle. If review does not have a compatible MCP client, note that
the rest of the app is fully usable without connecting one.

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
