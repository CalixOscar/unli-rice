import SwiftUI
import UnliRiceCore

/// Everything that decides what runs on its own: the autonomy slider, the
/// janitor's manual triggers, the ingest pipelines, and the two scheduling
/// switches.
///
/// This used to be `AutonomyPanel`, a 260pt column pinned to the right of every
/// screen. Every control in it is setup or a deliberate manual trigger — things
/// you touch when configuring the app or when you want something to happen
/// *now*, not while reading a note. Keeping them permanently on screen cost the
/// main column a fifth of the window on panes where none of it applied (Connect,
/// the graph, the retrospective), and it made a tool whose whole premise is
/// "invisible by default" present as a wall of knobs.
///
/// Moving it here also removes a constraint the old layout imposed on the
/// controls themselves: a `Toggle` reports its label's width as its ideal width,
/// so long labels used to push the column wider and clip its siblings. That's
/// why the switches were called "Routines" and "In background" with the
/// explanation exiled to a line underneath. With room to work in, the label can
/// say what the thing is.
struct AutomationView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Automation")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text("What Unli Rice does without being asked, and what it will only do when you press the button. Every structural change is queued for your approval either way — there is no delete.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AdvancedModeToggleCard()

                    if store.advancedModeEnabled {
                        AutonomyCard()
                        ScheduleCard()
                        JanitorCard()
                        IngestCard()
                    } else {
                        SimpleScanRootsCard()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Shared chrome, so the four sections read as one screen rather than four
/// transplanted panels.
private struct Card<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim.opacity(0.8))
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.white.opacity(0.01)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

private struct AutonomyCard: View {
    @EnvironmentObject var store: AppStore

    private let labels = ["Eco", "Balanced", "Aggressive"]
    private let descriptions = [
        "Only cosmetic, reversible actions run, and only while plugged in and idle. No merge/split proposals.",
        "Cosmetic actions run automatically. The janitor also scans for possible merges/splits and queues proposals — nothing structural applies without your tap.",
        "Janitor looks more often and proposes more eagerly. Still queues every structural change — this setting never grants auto-apply."
    ]

    var body: some View {
        Card(
            title: "Agent autonomy",
            subtitle: "How eagerly the janitor acts. Read by the background agent too, not just this window.",
            icon: "slider.horizontal.3"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Slider(value: Binding(
                    get: { Double(store.autonomyLevel) },
                    set: { store.autonomyLevel = Int($0.rounded()) }
                ), in: 0...2, step: 1)
                .tint(Theme.accent)
                .frame(maxWidth: 420)

                HStack {
                    ForEach(labels, id: \.self) { label in
                        Text(label.uppercased())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(
                                labels.firstIndex(of: label) == store.autonomyLevel
                                    ? Theme.accent : Theme.inkDim
                            )
                        if label != labels.last { Spacer() }
                    }
                }
                .frame(maxWidth: 420)

                Text(descriptions[store.autonomyLevel])
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.accent).frame(width: 2)
                    }
                    .padding(.leading, 8)
            }
        }
    }
}

/// The two switches that decide whether any of this is automatic at all.
private struct ScheduleCard: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Card(
            title: "Schedule",
            subtitle: "Both off by default, and they stay that way until you say otherwise — this app reads your own files, which is not something to start doing because an update shipped.",
            icon: "calendar.badge.clock"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                toggleRow(
                    isOn: $store.routinesEnabled,
                    title: "Run routines on a schedule",
                    detail: routineStatus
                )

                Divider().overlay(Theme.border)

                toggleRow(
                    isOn: Binding(
                        get: { store.backgroundAgentInstalled },
                        set: { store.setBackgroundAgent(enabled: $0) }
                    ),
                    title: "Keep working with the window closed",
                    detail: backgroundStatus,
                    disabled: !store.backgroundAgentBinaryFound && !store.backgroundAgentInstalled
                )
            }
        }
    }

    private func toggleRow(
        isOn: Binding<Bool>, title: String, detail: String, disabled: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .disabled(disabled)
        }
    }

    /// Says what it is rather than what it's called. "A launchd agent is
    /// installed" is true and useless; the thing the user is deciding is whether
    /// closing the window stops the app working.
    private var backgroundStatus: String {
        // A failure has to win over the description, or the toggle springing
        // back to off reads as the app ignoring the click.
        if let failure = store.backgroundAgentFailure {
            return "Couldn't turn this on: \(failure)"
        }
        if store.backgroundAgentInstalled {
            return "On — checks every 5 minutes whether the window is open or not."
        }
        if !store.backgroundAgentBinaryFound {
            return "Needs the packaged app — run Scripts/make-app.sh, then open Unli Rice.app."
        }
        return "Off — routines only run while this window is open."
    }

    private var routineStatus: String {
        guard store.routinesEnabled else {
            return "Off — nothing runs unless you press a button below."
        }
        let base = "Tue & Fri: ingest 9am, janitor 1pm."
        return store.autonomyLevel == 0
            ? base + " Eco waits for plugged-in and idle."
            : base
    }
}

/// The janitor's manual trigger.
///
/// "Preview" comes first and is styled as the primary action on purpose. The
/// janitor's contract is that you can always see what it would do before it does
/// anything, and a UI where "Run" is the obvious button quietly weakens that.
private struct JanitorCard: View {
    @EnvironmentObject var store: AppStore
    @State private var showingModelConfig = false

    var body: some View {
        Card(
            title: "Janitor",
            subtitle: "Tidies what's already here. With the schedule off, these two buttons are the only way it ever runs.",
            icon: "wand.and.stars"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    actionButton("Preview", color: Theme.accent) {
                        Task { await store.previewJanitor() }
                    }
                    actionButton("Run now", color: Theme.brass) {
                        Task { await store.runJanitorNow() }
                    }
                    if store.janitorBusy {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    }
                    Spacer()
                    Text("Similarity: \(store.similarityEngine.label)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkDim.opacity(0.8))
                }
                .disabled(store.janitorBusy)

                embeddingServerRow

                if let summary = store.janitorSummary {
                    Text(summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim)
                }

                // A preview is a claim about what would happen, so it has to be
                // specific enough to disagree with — hence each proposal's own
                // rationale rather than a count. The full width this pane has
                // means the rationale no longer wraps to four lines.
                if !store.janitorPreview.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(store.janitorPreview, id: \.fingerprint) { proposal in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(proposal.risk == .cosmetic ? "AUTO" : "QUEUE")
                                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                        .foregroundStyle(proposal.risk == .cosmetic ? Theme.accent : Theme.brass)
                                        .frame(width: 40, alignment: .leading)
                                    Text(proposal.rationale)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.inkDim)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
            }
        }
    }

    private var embeddingServerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(showingModelConfig ? "− Local embedding server" : "+ Local embedding server") {
                showingModelConfig.toggle()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.inkDim.opacity(0.85))

            if showingModelConfig {
                HStack(spacing: 8) {
                    TextField("http://localhost:1234/v1", text: $store.embeddingServerPath)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(6)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))

                    TextField("embedding model name", text: Binding(
                        get: { store.embeddingModelName ?? "" },
                        set: { store.embeddingModelName = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                }
                .frame(maxWidth: 520)

                Text("LM Studio or Ollama. Localhost only — your note titles are sent to it. Leave blank to use word overlap.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkDim.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
    }
}

/// The data pipelines: what fills the corpus, as opposed to what tidies it.
///
/// Preview is listed first and styled as the primary action, the same as the
/// janitor — and the reason is stronger here. These importers read the user's
/// own files, so being able to see exactly what would be taken, before anything
/// is copied, is what makes leaving the routines on a defensible choice rather
/// than a hopeful one.
private struct IngestCard: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Card(
            title: "Data pipelines",
            subtitle: "What fills the store, as opposed to what tidies it. Reads your Claude Code sessions and any folder you add.",
            icon: "doc.on.doc.fill"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    actionButton("Preview", color: Theme.accent) {
                        Task { await store.previewIngest() }
                    }
                    actionButton("Ingest now", color: Theme.brass) {
                        Task { await store.runIngestNow() }
                    }
                    if store.ingestBusy {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    }
                    Spacer()
                    Button("+ Add a folder to index") { store.chooseScanRoot() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                }
                .disabled(store.ingestBusy)

                // Both pipelines are named, including the one that isn't
                // running. `Pipelines.standard` drops LocalFileImporter
                // entirely when no folder is nominated — correct behaviour, but
                // the UI used to render that as silence, so a vault full of
                // notes simply never appeared and nothing on screen said why.
                VStack(alignment: .leading, spacing: 3) {
                    Label("Claude Code sessions", systemImage: "checkmark.circle")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.emerald)

                    if store.scanRoots.isEmpty {
                        Label(
                            "Local documents — off. No folders added, so nothing on disk is read.",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.brass)
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label(
                            "Local documents — \(store.scanRoots.count) folder\(store.scanRoots.count == 1 ? "" : "s"), searched recursively",
                            systemImage: "checkmark.circle"
                        )
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.emerald)
                    }
                }

                ForEach(store.scanRoots, id: \.self) { root in
                    HStack(spacing: 8) {
                        // The full path, not just the last component: two
                        // folders called "notes" in different projects are a
                        // realistic way to index the wrong one for months.
                        Text(root.path)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.inkDim)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button("remove") { store.removeScanRoot(root) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.inkDim.opacity(0.7))
                    }
                }

                if let summary = store.ingestSummary {
                    Text(summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim)
                }

                // A preview has to be specific enough to disagree with, so it
                // names the resources rather than counting them. It scrolls now
                // rather than stopping at eight and admitting there are more.
                if !store.ingestPreview.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(store.ingestPreview, id: \.title) { resource in
                                Text(resource.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkDim)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
        }
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
    }
}

private struct AdvancedModeToggleCard: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Card(
            title: "Advanced Features",
            subtitle: "Show background daemon configurations, janitorial autonomy levels, and detailed raw previews.",
            icon: "gearshape.2.fill"
        ) {
            HStack {
                Text("Enable Advanced Mode")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Toggle("", isOn: $store.advancedModeEnabled)
                    .toggleStyle(.switch)
            }
        }
    }
}

private struct SimpleScanRootsCard: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Card(
            title: "Import Folders",
            subtitle: "Choose folders containing text files. Markdown and text files in these folders are automatically imported as notes.",
            icon: "folder.badge.plus"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("NOMINATED FOLDERS")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
                    Spacer()
                    Button("+ Add Folder") { store.chooseScanRoot() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                }

                if store.scanRoots.isEmpty {
                    Text("No folders added yet. Click '+ Add Folder' to begin importing documents.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim.opacity(0.8))
                        .padding(.vertical, 4)
                } else {
                    ForEach(store.scanRoots, id: \.self) { root in
                        HStack(spacing: 8) {
                            Text(root.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.inkDim)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                            Button("remove") { store.removeScanRoot(root) }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.inkDim.opacity(0.7))
                        }
                    }
                }

                if let summary = store.ingestSummary {
                    Text(summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim)
                        .padding(.top, 4)
                }
            }
        }
    }
}
