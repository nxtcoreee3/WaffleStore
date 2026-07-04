import SwiftUI

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
    
    func localizedString(_ key: String) -> String {
        let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj")
        let bundle = path != nil ? Bundle(path: path!) : Bundle.main
        return NSLocalizedString(key, bundle: bundle ?? .main, comment: "")
    }
}

extension String {
    var localized: String {
        return LocalizationManager.shared.localizedString(self)
    }
}
