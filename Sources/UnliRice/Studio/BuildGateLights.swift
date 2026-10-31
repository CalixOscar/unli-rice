import SwiftUI
import UnliRiceCore

struct BuildGateLights: View {
    let result: BuildGate.Result?
    var showsLabels: Bool

    private var stages: [BuildGate.Stage] { BuildGate.Stage.allCases }

    var body: some View {
        HStack(spacing: showsLabels ? 10 : 6) {
            ForEach(stages, id: \.self) { stage in
                let light = result?.lights[stage] ?? .unknown("not read yet")
                VStack(spacing: 2) {
                    Image(systemName: Self.symbol(for: light))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(studio: Self.token(for: light), scheme: colorScheme))
                        .accessibilityLabel("\(Self.title(for: stage)): \(Self.spoken(for: light))")
                    if showsLabels {
                        Text(Self.title(for: stage))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    static func nextStep(_ result: BuildGate.Result?) -> String {
        nextStage(result).map { "Next: \(title(for: $0))" } ?? "All seven lights are in"
    }

    static func nextStage(_ result: BuildGate.Result?) -> BuildGate.Stage? {
        BuildGate.Stage.allCases.first { stage in
            let light = result?.lights[stage] ?? .unknown("not read yet")
            switch light {
            case .done, .notRequired, .skipped: return false
            default: return true
            }
        }
    }

    static func title(for stage: BuildGate.Stage) -> String {
        switch stage {
        case .idea: return "Idea"
        case .intent: return "Intent"
        case .spec: return "Spec"
        case .agents: return "Agents"
        case .premortem: return "Pre-mortem"
        case .build: return "Build"
        case .postmortem: return "Post-mortem"
        }
    }

    static func symbol(for light: BuildGate.Light) -> String {
        switch light {
        case .done: return "circle.fill"
        case .draft: return "circle"
        case .missing, .notRecorded: return "circle.dotted"
        case .skipped: return "slash.circle"
        case .notRequired: return "minus"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    static func token(for light: BuildGate.Light) -> StudioPalette.Token {
        switch light {
        case .done: return .lightDone
        case .draft: return .lightDraft
        case .unknown: return .lightUnknown
        default: return .lightMissing
        }
    }

    static func spoken(for light: BuildGate.Light) -> String {
        switch light {
        case .done: return "done"
        case .draft(let reason), .unknown(let reason): return reason
        case .missing: return "missing"
        case .notRecorded: return "not recorded"
        case .skipped(let reason): return "skipped: \(reason)"
        case .notRequired(let reason): return "not needed: \(reason)"
        }
    }
}
