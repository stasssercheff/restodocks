//
//  RestodocksApp.swift
//  Restodocks
//

import SwiftUI

@main
struct RestodocksApp: App {

    @StateObject private var appState = AppState()
    @StateObject private var accounts = AccountManager()
    @StateObject private var lang = LocalizationManager.shared
    @StateObject private var pro = ProAccess.shared

    var body: some Scene {
        WindowGroup {
            RootRouterView()
                .environmentObject(appState)
                .environmentObject(accounts)
                .environmentObject(lang)
                .environmentObject(pro)
                .tint(AppTheme.primary)
                .onAppear {
                    accounts.appState = appState
                }
        }
    }
}
