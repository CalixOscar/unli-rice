import AppKit
import SwiftUI
import UnliRiceCore

struct SleeveBackView: View {
    let sleeve: GardenCrate.Sleeve
    let result: BuildGate.Result?
    @State private var copied = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sleeve.name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(sleeve.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            if let slug = result?.slug {
                Text("Feature: \(slug)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }

            if sleeve.folderURL == nil {
                Text("This project has no folder, so it has no lights.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                side("SIDE A")
                ForEach(Array(zip([BuildGate.Stage.idea, .intent, .spec, .agents, .premortem], ["A1", "A2", "A3", "A4", "A5"])), id: \.0) { stage, number in
                    trackRow(stage: stage, number: number)
                }
                side("SIDE B")
                ForEach(Array(zip([BuildGate.Stage.build, .postmortem], ["B1", "B2"])), id: \.0) { stage, number in
                    trackRow(stage: stage, number: number)
                }
                ForEach(result?.issues ?? [], id: \.self) { issue in
                    Text(issue)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(BuildGateLights.nextStep(result))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let prompt = Self.prompt(sleeve: sleeve, result: result) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(prompt, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .liquidGlassCapsule(interactive: true)
                }
                Text("Lights show which files exist in this repo.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func side(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(Theme.textSecondary)
    }

    private func trackRow(stage: BuildGate.Stage, number: String) -> some View {
        let light = result?.lights[stage] ?? .unknown("not read yet")
        let word = BuildGateLights.spoken(for: light)
        return HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, alignment: .leading)
            Image(systemName: BuildGateLights.symbol(for: light))
                .font(.system(size: 12))
                .foregroundStyle(Color(studio: BuildGateLights.token(for: light), scheme: colorScheme))
            Text(BuildGateLights.title(for: stage))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(word)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(BuildGateLights.title(for: stage)): \(word)")
        .accessibilityAddTraits(.isStaticText)
    }

    static func prompt(sleeve: GardenCrate.Sleeve, result: BuildGate.Result?) -> String? {
        guard let folder = sleeve.folderURL, let result, let stage = BuildGateLights.nextStage(result) else { return nil }
        var lines = ["Project: \(sleeve.name), in \(folder.path)."]
        guard let slug = result.slug else {
            lines.append("This project has no docs/PLAN-*.md yet. Write the intent file for the next feature in docs/intent/, following AGENTS.md § \"The order, for every app\". Ask me what the feature is before you write anything.")
            lines.append("Follow AGENTS.md.")
            return lines.joined(separator: "\n")
        }
        lines.append("Feature: \(slug) (plan: docs/PLAN-\(slug).md).")
        let currentLight = result.lights[stage] ?? .unknown("not read yet")
        lines.append("Next stage: \(BuildGateLights.title(for: stage)). Right now: \(BuildGateLights.spoken(for: currentLight)).")
        switch stage {
        case .idea:
            lines.append("Write docs/idea/IDEA-\(slug).md. If this feature needs no idea brief, add the line \"**Idea:** not needed — <reason>\" to the plan's header instead.")
        case .intent:
            lines.append("Finish the intent file named on the plan's **Intent:** line. Its **Status:** line says approved only after I approve it.")
        case .spec:
            lines.append("Finish the spec file named on the plan's **Spec:** line. Its **Intent:** line must name the same intent file, and its **Status:** line says approved only after I approve it.")
        case .agents:
            lines.append("Make AGENTS.md at the repo root current for this work. If there is a CLAUDE.md, it needs a line that is exactly @AGENTS.md.")
        case .premortem:
            lines.append("Get the reviewer's pre-mortem of the plan into docs/dialogue/\(slug).md, answer it, and add the planner's settled turn after it.")
        case .build:
            lines.append("Build the plan's steps. When they are built, set the plan's **Stage:** line to 5.")
        case .postmortem:
            lines.append("Get the reviewer's post-mortem turn into docs/dialogue/\(slug).md, after the planner's settled turn.")
        }
        lines.append("Follow AGENTS.md.")
        return lines.joined(separator: "\n")
    }
}
