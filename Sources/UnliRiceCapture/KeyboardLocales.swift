import Foundation
import UIKit

/// The languages the user actually types in, read from their installed keyboards.
///
/// **Why this exists.** "Follow system" used to mean `Locale.current` — Settings →
/// General → Language & Region. That is the device's *display* language, and it is a poor
/// guess at what someone speaks into a microphone. An en-PH device with English and
/// Filipino keyboards installed was transcribed as en-PH every time, with nothing in the
/// UI to suggest the keyboard list even existed.
///
/// `UITextInputMode.activeInputModes` is the closest thing iOS offers to "languages this
/// person uses". It is not a promise — someone may type in a language they never speak,
/// and vice versa — so this only picks a **default** and an **ordering**. The picker still
/// lets any supported language be chosen explicitly.
///
/// What this deliberately does not attempt: code-switching. `SpeechTranscriber` takes one
/// locale per session, so Taglish is not solved by choosing a better default. See the
/// picker's footer, which now says so.
enum KeyboardLocales {

    /// Keyboard languages, in the order iOS reports them — the user's own priority order.
    /// Emoji and dictation input modes carry no primary language and are skipped.
    static func active() -> [Locale] {
        var seen = Set<String>()
        var out: [Locale] = []
        for mode in UITextInputMode.activeInputModes {
            guard let lang = mode.primaryLanguage, lang != "emoji" else { continue }
            let locale = Locale(identifier: lang)
            guard seen.insert(locale.identifier).inserted else { continue }
            out.append(locale)
        }
        return out
    }

    /// What "Follow system" should resolve to: the first keyboard language, falling back
    /// to `Locale.current` when there is nothing usable to read.
    ///
    /// Falling back matters — `activeInputModes` returns an empty array before the keyboard
    /// subsystem has been touched in a freshly launched process, and returning a garbage
    /// locale there would be worse than the region default this replaces.
    static func preferred() -> Locale {
        active().first ?? .current
    }

    /// A human-readable reason for the resolved default, shown under "Follow system" so the
    /// choice is not mysterious. Nil when we fell back to the region setting.
    static func explanation() -> String? {
        guard let first = active().first else { return nil }
        let name = Locale.current.localizedString(forIdentifier: first.identifier)
            ?? first.identifier
        let extra = active().count - 1
        if extra > 0 {
            return "From your keyboards — \(name), plus \(extra) more"
        }
        return "From your keyboard — \(name)"
    }
}
