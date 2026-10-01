import AppKit
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case brazilianPortuguese = "pt-BR"
    case russian = "ru"
    case arabic = "ar"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        case .spanish:
            return "Español"
        case .french:
            return "Français"
        case .german:
            return "Deutsch"
        case .italian:
            return "Italiano"
        case .brazilianPortuguese:
            return "Português (Brasil)"
        case .russian:
            return "Русский"
        case .arabic:
            return "العربية"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var layoutDirection: LayoutDirection {
        self == .arabic ? .rightToLeft : .leftToRight
    }

    /// Chinese locales keep the extra About links whose labels are short enough
    /// to stay readable; other locales show a reduced icon set instead.
    var isChinese: Bool {
        self == .simplifiedChinese || self == .traditionalChinese
    }

    var nsLayoutDirection: NSUserInterfaceLayoutDirection {
        self == .arabic ? .rightToLeft : .leftToRight
    }

    static func resolved(preferredLanguages: [String]) -> AppLanguage {
        for identifier in preferredLanguages {
            if let match = match(identifier) {
                return match
            }
        }
        return .english
    }

    static func match(_ identifier: String) -> AppLanguage? {
        let normalized = identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalized == "zh"
            || normalized.hasPrefix("zh-hans")
            || normalized.hasPrefix("zh-cn")
            || normalized.hasPrefix("zh-sg")
            || normalized.hasPrefix("zh-my") {
            return .simplifiedChinese
        }

        if normalized.hasPrefix("zh-hant")
            || normalized.hasPrefix("zh-tw")
            || normalized.hasPrefix("zh-hk")
            || normalized.hasPrefix("zh-mo") {
            return .traditionalChinese
        }

        if normalized == "pt" || normalized.hasPrefix("pt-br") {
            return .brazilianPortuguese
        }

        return allCases.first { language in
            let rawValue = language.rawValue.lowercased()
            return normalized == rawValue || normalized.hasPrefix("\(rawValue)-")
        }
    }
}
