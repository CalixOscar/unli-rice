import Foundation
import UnliRiceCore
import UnliRiceMLX

/// A finished question/answer pair, shown in the Assistant panel.
struct ChatTurn: Identifiable {
    let id = UUID()
    let question: String
    var answer: String
    var isDraft: Bool = false
}

enum ChatEngineStatus: Equatable {
    case notLoaded
    case loading(Double)
    case ready
    case unavailable(String)

    var label: String {
        switch self {
        case .notLoaded: return "not loaded yet"
        case .loading(let fraction): return "loading local model… \(Int(fraction * 100))%"
        case .ready: return "Qwen3-1.7B, on-device"
        case .unavailable(let reason): return "unavailable (\(reason))"
        }
    }
}

/// The chat panel — free-form Q&A over the corpus, and per-cluster duplicate
/// recommendations. See `JanitorChat` for why this can only ever produce text:
/// there is no path from a model's answer to a write. Resolving a cluster is
/// still, and can only ever be, a human pressing Accept/Reject.
extension AppStore {
    /// Asks a free-form question, using recent notes and the review queue as
    /// context. Appends to `chatHistory` so the panel reads as a conversation,
    /// even though (see `JanitorChat.ask`) no state is actually kept in the
    /// model between calls — each question resends its own context fresh.
    func askAssistant(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chatBusy else { return }

        chatBusy = true
        defer { chatBusy = false }

        let priorTurns = chatHistory.map { ($0.question, $0.answer) }
        let prompt = ChatContext.questionPrompt(
            trimmed, notes: notes, pendingClusters: pendingClusters, priorTurns: priorTurns
        )

        do {
            let chat = try await chatEngine()
            let answer = try await chat.ask(prompt)
            chatHistory.append(ChatTurn(question: trimmed, answer: answer))
        } catch {
            chatHistory.append(ChatTurn(question: trimmed, answer: "Couldn't reach the local model: \(error)"))
        }
    }

    /// A recommendation for one duplicate cluster: is this really the same
    /// note repeated, and if so, which copy looks like the keeper? Advisory
    /// only — the text is shown on the cluster's card; Accept/Reject is
    /// unaffected and still the only thing that changes the event log.
    func draftRecommendation(for cluster: ReviewCluster) async {
        guard clusterRecommendations[cluster.id] == nil else { return }
        clusterRecommendations[cluster.id] = "…"

        do {
            let chat = try await chatEngine()
            let answer = try await chat.ask(ChatContext.clusterRecommendationPrompt(cluster))
            clusterRecommendations[cluster.id] = answer
        } catch {
            clusterRecommendations[cluster.id] = "Couldn't reach the local model: \(error)"
        }
    }

    func clearChat() {
        chatHistory = []
    }

    // MARK: - The engine

    /// Loads the chat model once, on first use, and remembers a failure so a
    /// machine that can't load it doesn't retry on every message. Mirrors
    /// `AppStore+Janitor.swift`'s `similarityProvider()` — same reasoning: a
    /// failure here should degrade to "the assistant says so in the panel,"
    /// never a crash or a silently wrong answer.
    private func chatEngine() async throws -> JanitorChat {
        if let loaded = janitorChat { return loaded }

        chatEngineStatus = .loading(0)
        let chat = try await JanitorChat.load { fraction in
            Task { @MainActor [weak self] in
                self?.chatEngineStatus = .loading(fraction)
            }
        }
        janitorChat = chat
        chatEngineStatus = .ready
        return chat
    }
}
