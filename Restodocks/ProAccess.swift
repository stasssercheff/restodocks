import SwiftUI
import Combine

final class ProAccess: ObservableObject {

    static let shared = ProAccess()

    @Published var isPro: Bool {
        didSet { save() }
    }

    private init() {
        self.isPro = UserDefaults.standard.bool(forKey: "isPro")
    }

    private func save() {
        UserDefaults.standard.set(isPro, forKey: "isPro")
    }

    /// Активация через код
    func activateWithCode(_ code: String) -> Bool {
        if code == "RESTO2025" {
            isPro = true
            return true
        }
        return false
    }

    /// Прямое включение Pro
    func unlock() {
        isPro = true
    }
}
