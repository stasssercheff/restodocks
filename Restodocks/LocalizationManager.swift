import Foundation
import SwiftUI
import Combine

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// Языки выводятся из Localizable.json. Публичный доступ для LanguageSelectionView.
    private(set) var supportedLanguages: [String] = ["ru", "en"]

    // Текущий сотрудник (устанавливается при входе)
    var currentEmployeeId: String? {
        didSet {
            objectWillChange.send()
        }
    }

    // Ключ UserDefaults для текущего аккаунта
    private var langKey: String {
        if let employeeId = currentEmployeeId {
            return "selected_language_\(employeeId)"
        }
        return "selected_language_default"
    }

    var currentLang: String {
        get {
            let stored = UserDefaults.standard.string(forKey: langKey) ?? ""
            return stored.isEmpty ? defaultLanguage() : stored
        }
        set {
            UserDefaults.standard.set(newValue, forKey: langKey)
            objectWillChange.send()
        }
    }

    private func defaultLanguage() -> String {
        let preferred = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        return supportedLanguages.contains(String(preferred)) ? String(preferred) : "en"
    }

    var isLanguageSelected: Bool { true }

    func initializeLanguage() {}

    @Published private var translations: [String: [String: String]] = [:]

    private init() {
        loadJSON()
    }

    private func loadJSON() {
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "json") else {
            print("❌ ОШИБКА: Файл Localizable.json не найден в Bundle. Проверьте Target Membership!")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: [String: String]].self, from: data)
            let langCodes = Set(decoded.values.flatMap { $0.keys })
            DispatchQueue.main.async {
                self.translations = decoded
                self.supportedLanguages = Array(langCodes).sorted()
                print("✅ Словари загружены. Языки: \(self.supportedLanguages.joined(separator: ", "))")
                print("📱 Текущий язык: \(self.currentLang)")
            }
        } catch {
            print("❌ ОШИБКА Декодирования: \(error)")
        }
    }

    func t(_ key: String) -> String {
        guard !translations.isEmpty else { return key }

        if let translation = translations[key]?[currentLang], !translation.isEmpty {
            return translation
        }
        if let russian = translations[key]?["ru"], !russian.isEmpty {
            return russian
        }
        if let english = translations[key]?["en"], !english.isEmpty {
            return english
        }
        return key
    }

    func setLang(_ lang: String) {
        currentLang = lang
    }

    /// Название и флаг для отображения в UI (расширяемый список)
    static func displayInfo(for code: String) -> (name: String, flag: String) {
        switch code {
        case "ru": return ("Русский", "🇷🇺")
        case "en": return ("English", "🇺🇸")
        case "es": return ("Español", "🇪🇸")
        case "de": return ("Deutsch", "🇩🇪")
        case "fr": return ("Français", "🇫🇷")
        case "it": return ("Italiano", "🇮🇹")
        case "pt": return ("Português", "🇵🇹")
        default: return (code.uppercased(), "🏳️")
        }
    }
}
