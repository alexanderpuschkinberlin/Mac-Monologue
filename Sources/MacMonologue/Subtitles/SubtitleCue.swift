import Foundation

/// The four languages subtitles can be spoken in and written in.
enum SubtitleLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case german = "de"
    case english = "en"
    case french = "fr"
    case spanish = "es"

    var id: String { rawValue }

    /// In its own language, as a speaker of it would look for it.
    var nativeName: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        case .french: "Français"
        case .spanish: "Español"
        }
    }

    /// For the spoken-language picker, read by someone who may not speak it.
    var englishName: String {
        switch self {
        case .german: "German"
        case .english: "English"
        case .french: "French"
        case .spanish: "Spanish"
        }
    }

    var language: Locale.Language { Locale.Language(identifier: rawValue) }

    /// The regional variant speech recognition is asked for; it maps it to the
    /// nearest one it has.
    var speechLocale: Locale {
        switch self {
        case .german: Locale(identifier: "de-DE")
        case .english: Locale(identifier: "en-US")
        case .french: Locale(identifier: "fr-FR")
        case .spanish: Locale(identifier: "es-ES")
        }
    }

    /// ISO 639-2/T, which MP4 track headers carry.
    var threeLetterCode: String {
        switch self {
        case .german: "deu"
        case .english: "eng"
        case .french: "fra"
        case .spanish: "spa"
        }
    }

    /// The Mac's own language if it is one of the four, else English.
    static var systemDefault: SubtitleLanguage {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return SubtitleLanguage(rawValue: code) ?? .english
    }
}

/// A recognised word and when it was said, in seconds from the start of the file.
struct TimedWord: Equatable, Sendable {
    var text: String
    var start: Double
    var end: Double
}

/// One subtitle on screen: at most two lines, shown from `start` to `end`.
struct SubtitleCue: Equatable, Sendable {
    var start: Double
    var end: Double
    /// Lines separated by "\n".
    var text: String
}
