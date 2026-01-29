//
//  RestodocksApp.swift
//  Restodocks
//

import SwiftUI
import CoreData

@main
struct RestodocksApp: App {

    // Core Data
    let persistenceController = PersistenceController.shared

    // 🔐 app state
    @StateObject private var appState = AppState()

    // 👤 аккаунты
    @StateObject private var accounts = AccountManager()

    // 🌍 локализация
    @StateObject private var lang = LocalizationManager.shared

    // ⭐️ pro
    @StateObject private var pro = ProAccess.shared

    var body: some Scene {
        WindowGroup {
            RootRouterView()
                // ✅ ЕДИНСТВЕННЫЙ источник Core Data
                .environment(
                    \.managedObjectContext,
                    persistenceController.container.viewContext
                )
                .environmentObject(appState)
                .environmentObject(accounts)
                .environmentObject(lang)
                .environmentObject(pro)
                .tint(AppTheme.primary)
                .onAppear {
                    // ✅ Connect AccountManager to AppState
                    accounts.appState = appState
                }
        }
    }
}
