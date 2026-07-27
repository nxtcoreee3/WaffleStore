import SwiftUI
import Combine
import Combine

enum Language: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case chinese = "zh"
    case swedish = "sv"
    case norwegian = "no"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .chinese: return "中文"
        case .swedish: return "Svenska"
        case .norwegian: return "Norsk"
        }
    }
}

@MainActor
class LocalizationManager: ObservableObject {
    
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: Language {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
        }
    }
    
    init() {
        let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        self.currentLanguage = Language(rawValue: savedLanguage) ?? .english
    }
    
    nonisolated func localizedString(_ key: String) -> String {
        let langCode = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(key, bundle: bundle, comment: "")
        } else {
            return NSLocalizedString(key, comment: "")
        }
    }
}

extension String {
    nonisolated var localized: String {
        let langCode = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(self, bundle: bundle, comment: "")
        } else {
            return NSLocalizedString(self, comment: "")
        }
    }
}
