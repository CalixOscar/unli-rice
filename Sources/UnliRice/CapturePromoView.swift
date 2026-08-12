import AppKit
import SwiftUI
import UnliRiceCore

/// The iPhone companion, shown in the sidebar as a picture rather than a pitch.
///
/// The point of the app is that ideas happen away from the Mac, so the card
/// leads with what the phone screen actually looks like and what pressing the
/// mic does. Everything transactional — where to buy it, what it costs — is one
/// click away in the sheet, never on the card. The dismiss control is real and
/// permanent: an ad you can't turn off is a thing the user has to keep looking
/// at, which is exactly the failure mode this app is built against.
struct CapturePromoCard: View {
    @EnvironmentObject var store: AppStore
    @AppStorage(CapturePromo.dismissedKey) private var dismissed = false
    @State private var showingSheet = false
    @State private var hovering = false

    var body: some View {
        if !dismissed {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 0) {
                    Text("ON YOUR PHONE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 4)
                    if hovering {
                        Button(action: { dismissed = true }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Hide this — it won't come back")
                    }
                }

                Button(action: { showingSheet = true }) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Sized so the whole card still fits above the fold at
                        // the window's 600pt minimum height, sidebar rows and
                        // all — see `UnliRiceApp`'s frame.
                        CapturePhoneMockup(scale: 0.55)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("Ideas don't wait for your desk")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)

                        Text("Hold the mic, say the thing. It's transcribed on the phone and written to the same folder your Mac reads.")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 3) {
                            Text("See how it connects")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.accentColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .liquidGlass(cornerRadius: 8)
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
            .onHover { hovering = $0 }
            .sheet(isPresented: $showingSheet) {
                CapturePromoSheet()
                    .environmentObject(store)
            }
        }
    }
}

/// The long version: what the phone app is, and the three steps that put its
/// captures where this Mac can see them.
struct CapturePromoSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var phoneShardCount: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 10) {
                        CapturePhoneMockup(scale: 1.0)
                        Text("Unli Rice Capture")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("iPhone · free · MIT")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("The idea you had in the car")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Unli Rice is only as good as what reaches it, and most of what's worth remembering happens nowhere near a Mac. Capture is a mic button and a list: hold it, talk, let go. The transcript is made on the phone — the audio never leaves it — and lands in a folder of your choosing as an event log, the same append-only format this vault uses.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("CONNECTING IT THROUGH ICLOUD")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)

                            step(1, "Put your Unli Rice Folder in iCloud Drive.",
                                 "Anywhere under iCloud Drive works. That's the folder this Mac already exports context into and reads notes back out of.")
                            step(2, "On the iPhone, open Capture → gear → Select Sync Folder.",
                                 "The Files picker opens. Choose the same folder under iCloud Drive. The phone remembers it as a bookmark; you do this once.")
                            step(3, "Record. The capture syncs as its own file.",
                                 "The phone writes `events-phone-<id>.jsonl` into that folder and reads back any notes tagged with the project tab you're on, so the phone list isn't a dead end.")
                        }

                        folderStatus

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Free and open source, same as Unli Rice on the Mac. No rush on any of this either — the Mac app is complete without it. Capture exists for the days you're not at the Mac at all.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button(action: { CapturePromo.openInfoPage() }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.right.square")
                                    Text("Read more about Capture")
                                }
                                .font(.system(size: 11.5, weight: .medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .foregroundStyle(Theme.accentColor)
                                .solidControl(cornerRadius: 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
            }

            Divider().opacity(0.15)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(Theme.onAccent)
                    .background(Theme.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(14)
        }
        .frame(width: 640, height: 560)
        .background(Theme.bgMain)
        .onAppear { phoneShardCount = CapturePromo.phoneShardCount(in: store.exportFolderURL) }
    }

    /// A receipt, not a claim. The folder is either inside iCloud Drive or it
    /// isn't, and either the phone has written into it or it hasn't — both are
    /// things this app can check rather than assert. See the Trust Center for
    /// the same rule applied to MCP connections.
    @ViewBuilder
    private var folderStatus: some View {
        let folder = store.exportFolderURL
        let inCloud = CapturePromo.isInICloudDrive(folder)

        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR FOLDER RIGHT NOW")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)

            if let folder {
                Text(folder.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)

                statusLine(
                    inCloud ? "checkmark.circle.fill" : "exclamationmark.circle",
                    inCloud ? Theme.emerald : Theme.brass,
                    inCloud
                        ? "This folder is inside iCloud Drive, so your phone can reach it."
                        : "This folder isn't in iCloud Drive, so the phone can't see it. Move it under iCloud Drive first, then re-pick it here."
                )
            } else {
                statusLine(
                    "exclamationmark.circle", Theme.brass,
                    "No Unli Rice Folder set yet. Set one under More → The folder your AI can read, somewhere inside iCloud Drive."
                )
            }

            if let count = phoneShardCount, count > 0 {
                statusLine("iphone", Theme.accentColor,
                           "\(count) phone capture file\(count == 1 ? "" : "s") already in this folder.")
            } else if folder != nil {
                statusLine("iphone.slash", Theme.textSecondary,
                           "Nothing written by a phone in this folder yet.")
            }

            // Said plainly rather than left to be discovered: the phone half of
            // the sync ships, the Mac half of it doesn't read those files back
            // into this vault yet. Claiming otherwise is the exact failure this
            // repo already fixed once for MCP status.
            Text("Heads up: this build of the Mac app doesn't yet fold those phone files into your notes automatically — the phone writes and reads them, the Mac side of that pickup is still to come.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(12)
        .liquidGlass(cornerRadius: 6)
    }

    private func statusLine(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 13)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accentColor)
                .frame(width: 18, height: 18)
                .background(Theme.accentSoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A drawing of the iPhone app, not a screenshot.
///
/// Deliberately drawn in SwiftUI rather than shipped as a PNG: it's a handful
/// of shapes, it costs nothing in the bundle, and it re-tints itself in light
/// and dark alongside the rest of the window instead of being a rectangle of
/// somebody else's theme sitting in the sidebar. Mirrors the real layout in
/// `Sources/UnliRiceCapture/CaptureView.swift` — title, project tab pills, mic
/// with its glow ring, then the capture list.
struct CapturePhoneMockup: View {
    var scale: CGFloat = 1.0

    private var w: CGFloat { 168 * scale }
    private var h: CGFloat { 316 * scale }

    var body: some View {
        VStack(spacing: 9 * scale) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                Text("Unli Rice")
                    .font(.system(size: 13 * scale, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                Text("Voice Capture & Memory")
                    .font(.system(size: 7 * scale, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4 * scale) {
                pill("Unli Thoughts", selected: true)
                pill("Nuptia", selected: false)
                Spacer(minLength: 0)
            }

            VStack(spacing: 7 * scale) {
                ZStack {
                    Circle()
                        .fill(Theme.accentColor.opacity(0.16))
                        .frame(width: 52 * scale, height: 52 * scale)
                    Circle()
                        .fill(Theme.accentColor)
                        .frame(width: 40 * scale, height: 40 * scale)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15 * scale))
                        .foregroundStyle(Theme.onAccent)
                }
                Text("Press and hold mic to record")
                    .font(.system(size: 7 * scale))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10 * scale)
            .background(Theme.bgField)
            .clipShape(RoundedRectangle(cornerRadius: 12 * scale))

            VStack(alignment: .leading, spacing: 5 * scale) {
                Text("ON-DEVICE CAPTURES (2)")
                    .font(.system(size: 6.5 * scale, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                captureRow("Rice cooker idea for the demo")
                captureRow("Ask about the folder naming")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10 * scale)
        .padding(.bottom, 10 * scale)
        // Clears the Dynamic Island drawn in the overlay below.
        .padding(.top, 19 * scale)
        .frame(width: w, height: h, alignment: .top)
        .background(Theme.bgMain)
        .clipShape(RoundedRectangle(cornerRadius: 22 * scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                .strokeBorder(Theme.borderLight, lineWidth: 2 * scale)
        )
        .overlay(alignment: .top) {
            // The Dynamic Island, which is what makes the rectangle read as a
            // phone at 62% scale in a 190pt sidebar.
            Capsule()
                .fill(Theme.textPrimary.opacity(0.85))
                .frame(width: 40 * scale, height: 9 * scale)
                .padding(.top, 4 * scale)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 9 * scale, x: 0, y: 4 * scale)
    }

    private func pill(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 7 * scale, weight: selected ? .bold : .medium))
            .lineLimit(1)
            .padding(.horizontal, 7 * scale)
            .padding(.vertical, 3.5 * scale)
            .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
            .background(selected ? Theme.accentColor : Theme.solidFill)
            .clipShape(Capsule())
    }

    private func captureRow(_ title: String) -> some View {
        HStack(spacing: 5 * scale) {
            Image(systemName: "waveform")
                .font(.system(size: 7 * scale))
                .foregroundStyle(Theme.accentColor)
            Text(title)
                .font(.system(size: 7 * scale, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7 * scale)
        .padding(.vertical, 5 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgField)
        .clipShape(RoundedRectangle(cornerRadius: 7 * scale))
    }
}

enum CapturePromo {
    static let dismissedKey = "unliRice.capturePromoDismissed"

    /// Where "read more" goes. The project's own page, not a store listing:
    /// the iPhone app is not something this window should be selling in a
    /// sidebar, and a page that explains the pipeline is more use than a
    /// checkout anyway.
    static let infoPageURL = URL(string: "https://calmdownoscar.com/unlirice")!

    static func openInfoPage() {
        NSWorkspace.shared.open(infoPageURL)
    }

    /// iCloud Drive is `~/Library/Mobile Documents/com~apple~CloudDocs/…` on
    /// disk regardless of what Finder shows in the sidebar, so the path is the
    /// thing worth checking.
    static func isInICloudDrive(_ url: URL?) -> Bool {
        guard let path = url?.path else { return false }
        return path.contains("/Library/Mobile Documents/")
    }

    /// Counts shard files a phone has published into the folder. Returns nil
    /// when there's no folder to look in; `0` genuinely means "looked, found
    /// none", which is a different answer and displayed as one.
    static func phoneShardCount(in folder: URL?) -> Int? {
        guard let folder else { return nil }
        let needsStop = folder.startAccessingSecurityScopedResource()
        defer { if needsStop { folder.stopAccessingSecurityScopedResource() } }

        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return nil
        }
        return names.filter { $0.hasPrefix("events-phone-") && $0.hasSuffix(".jsonl") }.count
    }
}
