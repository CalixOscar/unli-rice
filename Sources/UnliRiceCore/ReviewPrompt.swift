import Foundation

/// Decides *when* to ask for a rating. Deliberately knows nothing about StoreKit, so the
/// rule can be tested without a store, a device, or a real prompt being burned.
///
/// **Apple allows three prompts per 365 days and silently drops the rest.** That budget
/// is the whole design constraint: an app that asks at the first trivial milestone spends
/// its only good chance on someone who has barely used it. UnliDisk hit exactly this —
/// its prompt fired once at a single threshold, set a permanent boolean, and threw the
/// other two away, so a user who cleared 5 GB in month one and 60 GB in month six was
/// never asked at the better moment.
///
/// So: a ladder of milestones that get harder, a floor between asks, and a hard cap.
///
/// **What this deliberately does not do is gate on sentiment.** Asking "how do you like
/// it?" and routing only happy users to the store is review manipulation under App Store
/// Review Guideline 1.1.7, and it is a rejection risk on an app that already has a
/// rejection history. The system sheet asks everyone the same way; that is the point of it.
public struct ReviewPrompt: Equatable, Sendable {

    /// Milestones worth interrupting for, in order. Note counts rather than launches:
    /// a corpus that has grown is evidence the app is being used, where a launch count
    /// is evidence of nothing.
    ///
    /// The Mac app's rungs. Capture on iPhone passes its own to ``milestoneToAsk`` —
    /// a phone capture is a thirty-second voice note, so a hundred of them is a different
    /// amount of evidence than a hundred notes in a desktop corpus.
    public static let milestones = [100, 500, 2000]

    /// Unli Rice Capture's rungs, in captures durably saved.
    public static let captureMilestones = [10, 50, 200]

    /// Apple's own ceiling is three per 365 days. Staying under it is not enough — three
    /// asks in one week would be technically legal and obviously wrong.
    public static let minimumDaysBetweenAsks = 120
    public static let maximumAsksPerInstall = 3

    public struct State: Codable, Equatable, Sendable {
        public var asksMade: Int
        public var lastAsk: Date?
        /// The highest milestone already used, so the same one never asks twice.
        public var highestMilestoneUsed: Int
        /// Process launches seen, counted by ``markSessionStart``-style callers.
        ///
        /// `0` means the counter did not exist when this state was written — an install
        /// that predates the gate, which by definition is past its first session. `1` is
        /// literally a first session and is the only value that blocks.
        public var sessionCount: Int

        public init(asksMade: Int = 0,
                    lastAsk: Date? = nil,
                    highestMilestoneUsed: Int = 0,
                    sessionCount: Int = 0) {
            self.asksMade = asksMade
            self.lastAsk = lastAsk
            self.highestMilestoneUsed = highestMilestoneUsed
            self.sessionCount = sessionCount
        }

        /// Hand-written so a field added later reads back as its default rather than
        /// throwing. Synthesised `Codable` does not fall back to property defaults for a
        /// missing key, and the call site treats a decode failure as "no state at all" —
        /// which would silently refill a budget that is meant never to refill.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            asksMade = try c.decodeIfPresent(Int.self, forKey: .asksMade) ?? 0
            lastAsk = try c.decodeIfPresent(Date.self, forKey: .lastAsk)
            highestMilestoneUsed = try c.decodeIfPresent(Int.self, forKey: .highestMilestoneUsed) ?? 0
            sessionCount = try c.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        }
    }

    /// The state after counting a launch. Pure, so the caller decides when to persist.
    public static func recordSessionStart(_ state: State) -> State {
        var updated = state
        updated.sessionCount += 1
        return updated
    }

    /// Whether to ask now, and which milestone it would spend.
    ///
    /// Returns the milestone rather than a bare Bool so the caller can record exactly
    /// what was consumed — recording "asked" without recording *which* rung is how a
    /// ladder collapses back into a single boolean.
    public static func milestoneToAsk(noteCount: Int,
                                      state: State,
                                      milestones: [Int] = ReviewPrompt.milestones,
                                      now: Date = Date()) -> Int? {
        // Never during the first session. Implemented literally rather than left to
        // emerge from the note-count thresholds — those would very probably cover it,
        // but "very probably" is not what the guardrail says.
        guard state.sessionCount != 1 else { return nil }

        guard state.asksMade < maximumAsksPerInstall else { return nil }

        if let last = state.lastAsk {
            let days = now.timeIntervalSince(last) / 86_400
            guard days >= Double(minimumDaysBetweenAsks) else { return nil }
        }

        // The highest milestone reached that has not been used. Highest, not lowest:
        // someone who arrives with 600 notes should be asked at 500, not walked up
        // from 100 over three separate prompts.
        return milestones
            .filter { noteCount >= $0 && $0 > state.highestMilestoneUsed }
            .max()
    }

    /// The state after spending an ask. Pure, so the caller decides when to persist.
    public static func recordAsk(_ state: State, milestone: Int, now: Date = Date()) -> State {
        State(asksMade: state.asksMade + 1,
              lastAsk: now,
              highestMilestoneUsed: max(state.highestMilestoneUsed, milestone))
    }
}
