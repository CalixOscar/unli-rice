import Foundation
import SwiftUI
import UnliRiceCore

struct GuardrailsGroundingView: View {
    @EnvironmentObject var store: AppStore
    @State private var mirrorWritten: Date?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 20) {
                grounding.frame(maxWidth: .infinity, alignment: .top)
                guardrails.frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(24)
        }
    }

    private var grounding: some View {
        TabDeck(title: "Grounding", subtitle: "What your AI knows", accent: .grounding) {
            VStack(alignment: .leading, spacing: 10) {
                shelf
                Rectangle().fill(Theme.textSecondary.opacity(0.3)).frame(height: 2)
                labels
                HStack(spacing: 10) {
                    groundingButton("Open notes") { store.showAllNotes() }
                    groundingButton("Open the folder") { store.showAIFolder() }
                    groundingButton("Details") { store.showHome() }
                }
            }
        }
        .task(id: store.exportFolderURL) {
            let folder = store.exportFolderURL ?? URL(fileURLWithPath: NSString(string: "~/Documents/Unli Rice").expandingTildeInPath, isDirectory: true)
            mirrorWritten = await Task.detached {
                let accessed = folder.startAccessingSecurityScopedResource()
                defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
                return try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("READ ME FIRST.md").path)[.modificationDate] as? Date
            }.value
        }
    }

    private var shelf: some View {
        HStack(alignment: .bottom, spacing: 12) {
            let notes = store.errorMessage == nil ? "\(store.notes.filter { !$0.archived }.count)" : "—"
            groundingColumn(value: notes, bar: filledBar(height: 190, opacity: 1), accessibilityLabel: "Your notes: \(notes)")
            let age = Self.age(mirrorWritten, now: Date())
            groundingColumn(value: age, bar: filledBar(height: 137, opacity: 0.7), accessibilityLabel: "The folder your AI reads: \(mirrorWritten == nil ? "not written yet" : "written \(age) ago")")
            groundingColumn(value: "Later", bar: dashedBar, accessibilityLabel: "Claude Code memory files: coming later")
            groundingColumn(value: "Later", bar: dashedBar, accessibilityLabel: "Codex memory files: coming later")
        }
        .frame(height: 230, alignment: .bottom)
    }

    private func groundingColumn<Bar: View>(value: String, bar: Bar, accessibilityLabel: String) -> some View {
        VStack(spacing: 6) {
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(value == "Later" ? Theme.textSecondary : Theme.textPrimary)
            bar
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func filledBar(height: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(studio: .grounding, scheme: colorScheme).opacity(opacity)).frame(height: height)
    }

    private var dashedBar: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color(studio: .grounding, scheme: colorScheme).opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .frame(height: 57)
    }

    private var labels: some View {
        HStack(alignment: .top, spacing: 12) {
            label("Your notes")
            label("The folder your AI reads")
            label("Claude Code memory files")
            label("Codex memory files")
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: .infinity).accessibilityHidden(true)
    }

    private func groundingButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 8).liquidGlassCapsule(interactive: true)
    }

    private var guardrails: some View {
        TabDeck(title: "Guardrails", subtitle: "What your AI must do", accent: .guardrails) {
            VStack(alignment: .leading, spacing: 14) {
                houseRules
                tiles
                Text("Did your AI follow the rules? Checks are coming later.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.textSecondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])) }
            }
        }
    }

    private var houseRules: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HOUSE RULES · \(presetName.uppercased())").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(Color(studio: .guardrails, scheme: colorScheme)).lineLimit(1)
                Spacer()
                Button("Edit") { store.showHouseRules() }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 5).liquidGlassCapsule(interactive: true).accessibilityLabel("Edit House Rules")
            }
            if Self.ruleLines(store.houseRulesText).isEmpty {
                Text("No House Rules yet.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(Self.ruleLines(store.houseRulesText), id: \.self) { line in
                    Text(verbatim: line).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                }
            }
        }
        .padding(18)
        .background { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(studio: .background, scheme: colorScheme)) }
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(studio: .guardrails, scheme: colorScheme).opacity(0.35), lineWidth: 1) }
    }

    private var tiles: some View {
        HStack(spacing: 12) {
            Button { store.showNeedsYou() } label: { tileLabel(Text("\(store.pending.count + store.unreadNoticeCount)").font(.system(size: 40, weight: .bold)).foregroundStyle(Color(studio: .notes, scheme: colorScheme)), caption: "Need you") }
                .buttonStyle(.plain).accessibilityLabel("Need you: \(store.pending.count + store.unreadNoticeCount)")
            Button { store.showTrustCenter() } label: { tileLabel(Image(systemName: safetySymbol).font(.system(size: 36)).foregroundStyle(safetyColor), caption: safetyCaption) }
                .buttonStyle(.plain).accessibilityLabel(safetyCaption)
            Button { store.showArchived() } label: { tileLabel(Text("\(store.archivedNotes.count)").font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.textPrimary), caption: "Archived") }
                .buttonStyle(.plain).accessibilityLabel("Archived: \(store.archivedNotes.count)")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tileLabel<Content: View>(_ big: Content, caption: String) -> some View {
        VStack(spacing: 6) { big; Text(caption).font(.system(size: 13)).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center) }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 20)
            .background { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(studio: .background, scheme: colorScheme)) }
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.textSecondary.opacity(0.2), lineWidth: 1) }
    }

    private var presetName: String {
        let normalized = HouseRulesRevision.normalized(store.houseRulesText)
        return (HouseRulesPreset.builtIn + store.customHouseRulesPresets).first { HouseRulesRevision.normalized($0.body) == normalized }?.title ?? "Your own rules"
    }

    private var safetySymbol: String {
        if store.trustChecks.isEmpty { return "shield" }
        if store.trustChecks.contains(where: { $0.state == .failed }) { return "xmark.shield" }
        if store.trustChecks.contains(where: { $0.state == .attention }) { return "exclamationmark.shield" }
        return "checkmark.shield"
    }

    private var safetyColor: Color {
        if store.trustChecks.isEmpty { return Theme.textSecondary }
        if store.trustChecks.contains(where: { $0.state == .failed }) { return Color(studio: .guardrails, scheme: colorScheme) }
        if store.trustChecks.contains(where: { $0.state == .attention }) { return Color(studio: .notes, scheme: colorScheme) }
        return Color(studio: .garden, scheme: colorScheme)
    }

    private var safetyCaption: String {
        if store.trustChecks.isEmpty { return "Not checked yet" }
        if store.trustChecks.contains(where: { $0.state == .failed }) { return "Safety checks failed" }
        if store.trustChecks.contains(where: { $0.state == .attention }) { return "Safety checks need a look" }
        return "Safety checks pass"
    }

    static func age(_ date: Date?, now: Date) -> String {
        guard let date else { return "—" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    static func ruleLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("<!--") }
            .map {
                var line = String($0)
                for prefix in ["- ", "* ", "• "] where line.hasPrefix(prefix) { line.removeFirst(prefix.count); break }
                return line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            }
            .prefix(3)
            .map { String($0) }
    }
}

private struct TabDeck<Content: View>: View {
    let title: String
    let subtitle: String
    let accent: StudioPalette.Token
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, subtitle: String, accent: StudioPalette.Token, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.accent = accent; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased()).font(.system(size: 13, weight: .bold)).tracking(1.5).foregroundStyle(Color(studio: accent, scheme: colorScheme))
                Spacer()
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            content
        }
        .padding(20)
        .background(Color(studio: .surface, scheme: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
