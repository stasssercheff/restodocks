import Foundation
import SwiftUI
import Combine

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    // Используем @AppStorage для автоматической синхронизации с UserDefaults
    @AppStorage("selected_language") var currentLang: String = "ru" {
        didSet {
            // При смене языка принудительно уведомляем SwiftUI об обновлении
            objectWillChange.send()
        }
    }

    @Published private var translations: [String: [String: String]] = [:]

    private init() {
        loadJSON()
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
            }
        } catch {
            print("❌ ОШИБКА Декодирования: \(error)")
        }
    }

    // Функция перевода
    func t(_ key: String) -> String {
        guard !translations.isEmpty else { return key }
        
        return translations[key]?[currentLang]
            ?? translations[key]?["en"]
            ?? key
    }

    func setLang(_ lang: String) {
        currentLang = lang
    }
}
