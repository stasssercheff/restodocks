import SwiftUI

@main
struct RestodocksApp: App {

    // НЕ singleton
    @StateObject private var accounts = AccountManager()

    // singleton — ок
    @StateObject private var lang = LocalizationManager.shared
    @StateObject private var pro = ProAccess.shared

    var body: some Scene {
        WindowGroup {
            RootRouterView()
                .environmentObject(accounts)
                .environmentObject(lang)
                .environmentObject(pro)
                .tint(AppTheme.primary)   // 🔥 ВСЁ приложение в бренде
        }
    }
}
