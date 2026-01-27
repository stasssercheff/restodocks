import Foundation
import Combine

final class AppState: ObservableObject {

    /// пользователь вошёл / зарегистрирован
    @Published var isLoggedIn: Bool = false

    /// первый запуск приложения
    @Published var isFirstLaunch: Bool = true
}