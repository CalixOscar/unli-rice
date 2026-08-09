import Foundation

/// Turns a handful of selected notes into text to hand to whatever AI the user
/// already has — Claude, ChatGPT, whatever's installed. Nothing here reasons
/// about the notes. Composing loose ideas into a plan is a judgement call, and
/// this app has been careful never to fake that; the honest move is to hand
/// the raw material to something that can actually do it, with a preamble that
/// says exactly what's being asked and nothing more.
///
/// Pure and synchronous on purpose — no service, no I/O, no network. It cannot
/// call anything, so it cannot become a second place this app talks to a model.
public enum ShareToAI {
    /// States the material honestly rather than presuming what should happen to
    /// it — "turn this into a plan" already answers a question that belongs to
    /// whichever model receives it.
    public static let preamble = "Here are my thoughts — they're a mess. Please help me compose them into something clearer."

    /// Joins the given notes, unedited, under the preamble. Titles and bodies
    /// only, in the order given — no truncation, no summarising, no reordering
    /// by relevance. Anything smarter than concatenation would risk quietly
    /// dropping content before the user ever sees what was cut.
    public static func compose(_ notes: [Note]) -> String {
        guard !notes.isEmpty else { return "" }
        var text = preamble + "\n\n"
        for note in notes {
            text += "— \(note.title) —\n\(note.body)\n\n"
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Characters ÷ 4, the same rough conversion used everywhere else in this
    /// app that estimates size before something leaves the device. An estimate,
    /// and every surface that shows it says so — this is arithmetic, not a
    /// judgement about whether the size is fine.
    public static func estimatedTokens(_ text: String) -> Int {
        (text.count + 3) / 4
    }
}
