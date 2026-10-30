import Foundation

public enum StudioPalette {
    public enum Mode: String, CaseIterable, Sendable {
        case dark
        case light
    }

    public enum Token: String, CaseIterable, Sendable {
        case background, surface, textPrimary, textSecondary
        case garden, branches, notes, grounding, guardrails
        case lightDone, lightDraft, lightMissing, lightUnknown
        case stickerFineFill, stickerNeedsYouFill, stickerNoStatusFill, stickerCantReadFill
        case stickerDarkText, stickerLightText
        case cover0, cover1, cover2, cover3, cover4, cover5, cover6, cover7, coverText, coverSubtext
    }

    public struct Pair: Sendable {
        public let foreground: Token
        public let background: Token
        public let minimum: Double

        public init(foreground: Token, background: Token, minimum: Double) {
            self.foreground = foreground
            self.background = background
            self.minimum = minimum
        }
    }

    public static func hex(_ token: Token, _ mode: Mode) -> String {
        switch token {
        case .background: return mode == .dark ? "#0E0F12" : "#F5F5F7"
        case .surface: return mode == .dark ? "#15171C" : "#FFFFFF"
        case .textPrimary: return mode == .dark ? "#F2F3F5" : "#1D1D1F"
        case .textSecondary: return mode == .dark ? "#9AA0AB" : "#5E636E"
        case .garden: return mode == .dark ? "#3DDC97" : "#0B7A4B"
        case .branches: return mode == .dark ? "#5AA9FF" : "#1F5FBF"
        case .notes: return mode == .dark ? "#FFB547" : "#8F5300"
        case .grounding: return mode == .dark ? "#6FD3D9" : "#0B6B70"
        case .guardrails: return mode == .dark ? "#FF8A6B" : "#B23C1C"
        case .lightDone: return mode == .dark ? "#3DDC97" : "#14915C"
        case .lightDraft: return mode == .dark ? "#FFB547" : "#B86E00"
        case .lightMissing: return mode == .dark ? "#8A909B" : "#7A808B"
        case .lightUnknown: return mode == .dark ? "#6B707A" : "#878C96"
        case .stickerFineFill: return "#3DDC97"
        case .stickerNeedsYouFill: return "#FFB547"
        case .stickerNoStatusFill: return "#C9D3E0"
        case .stickerCantReadFill: return "#4A4F59"
        case .stickerDarkText: return "#0E0F12"
        case .stickerLightText: return "#F2F3F5"
        case .cover0: return "#1F3B2E"
        case .cover1: return "#3A2A14"
        case .cover2: return "#1C2A3D"
        case .cover3: return "#3A1F2B"
        case .cover4: return "#2E2414"
        case .cover5: return "#26272D"
        case .cover6: return "#1E3336"
        case .cover7: return "#2B2B2E"
        case .coverText: return "#F2F3F5"
        case .coverSubtext: return "#C9CDD4"
        }
    }

    public static let pairs: [Pair] = {
        let text: [Token] = [.textPrimary, .textSecondary, .garden, .branches, .notes, .grounding, .guardrails]
        var result = text.flatMap { token in
            [Pair(foreground: token, background: .background, minimum: 4.5),
             Pair(foreground: token, background: .surface, minimum: 4.5)]
        }
        result += [
            Pair(foreground: .stickerDarkText, background: .stickerFineFill, minimum: 4.5),
            Pair(foreground: .stickerDarkText, background: .stickerNeedsYouFill, minimum: 4.5),
            Pair(foreground: .stickerDarkText, background: .stickerNoStatusFill, minimum: 4.5),
            Pair(foreground: .stickerLightText, background: .stickerCantReadFill, minimum: 4.5)
        ]
        let covers: [Token] = [.cover0, .cover1, .cover2, .cover3, .cover4, .cover5, .cover6, .cover7]
        result += covers.flatMap { cover in
            [Pair(foreground: .coverText, background: cover, minimum: 4.5),
             Pair(foreground: .coverSubtext, background: cover, minimum: 4.5)]
        }
        result += [
            Pair(foreground: .lightDone, background: .surface, minimum: 3),
            Pair(foreground: .lightDraft, background: .surface, minimum: 3),
            Pair(foreground: .lightMissing, background: .surface, minimum: 3),
            Pair(foreground: .lightUnknown, background: .surface, minimum: 3)
        ]
        return result
    }()

    public static func contrastRatio(_ a: String, _ b: String) -> Double {
        let first = relativeLuminance(parse(a))
        let second = relativeLuminance(parse(b))
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func parse(_ value: String) -> (Double, Double, Double) {
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        precondition(hex.count == 6, "hex must be #RRGGBB")
        let channels = stride(from: 0, to: 6, by: 2).map { offset -> Double in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            guard let number = UInt8(hex[start..<end], radix: 16) else { preconditionFailure("invalid hex") }
            return Double(number) / 255
        }
        return (channels[0], channels[1], channels[2])
    }

    private static func relativeLuminance(_ rgb: (Double, Double, Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
    }
}
