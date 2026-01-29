import Foundation
import SwiftUI
import Combine

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    // Используем @AppStorage для автоматической синхронизации с UserDefaults
    @AppStorage("selected_language") var currentLang: String = "" {
        didSet {
            // При смене языка принудительно уведомляем SwiftUI об обновлении
            objectWillChange.send()
        }
    }

    // Проверяем, выбран ли язык при запуске
    var isLanguageSelected: Bool {
        !currentLang.isEmpty
    }

    // Устанавливаем язык по умолчанию при первом запуске
    func initializeLanguage() {
        if currentLang.isEmpty {
            // Определяем язык системы
            let preferredLanguage = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"

            // Поддерживаемые языки
            let supportedLanguages = ["ru", "en", "es", "de", "fr"]

            if supportedLanguages.contains(preferredLanguage) {
                currentLang = String(preferredLanguage)
            } else {
                currentLang = "en" // Английский по умолчанию
            }
        }
    }

    @Published private var translations: [String: [String: String]] = [:]

    private init() {
        loadJSON()
        initializeLanguage()
    }

    private func loadJSON() {
        // Убедитесь, что файл в Xcode называется именно Localizable.json (с большой L)
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "json") else {
            print("❌ ОШИБКА: Файл Localizable.json не найден в Bundle. Проверьте Target Membership!")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            // Декодируем словарь [Ключ: [Язык: Перевод]]
            let decoded = try JSONDecoder().decode([String: [String: String]].self, from: data)
            
            // Выполняем обновление в основном потоке для безопасности UI
            DispatchQueue.main.async {
                self.translations = decoded
                print("✅ Словари успешно загружены. Ключей: \(decoded.count)")
                print("📱 Текущий язык: \(self.currentLang)")
            }
        } catch {
            print("❌ ОШИБКА Декодирования: \(error)")
        }
    }

    // Функция перевода
    func t(_ key: String) -> String {
        guard !translations.isEmpty else { return key }

        // Сначала пробуем текущий язык
        if let translation = translations[key]?[currentLang], !translation.isEmpty {
            return translation
        }

        // Fallback на русский
        if let russian = translations[key]?["ru"], !russian.isEmpty {
            return russian
        }

        // Fallback на английский
        if let english = translations[key]?["en"], !english.isEmpty {
            return english
        }

        // Возвращаем ключ если ничего не найдено
        return key
    }

    func setLang(_ lang: String) {
        currentLang = lang
    }
}
