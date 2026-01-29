//
//  RootRouterView.swift
//  Restodocks
//

import SwiftUI

struct RootRouterView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var lang: LocalizationManager
    @AppStorage("language_selection_completed") var languageSelected = false

    var body: some View {
        Group {
            // Показываем welcome screen если пользователь не вошел
            if !appState.isLoggedIn {
                WelcomeView()
                    .transition(.opacity)
            } else {
                // Основное приложение
                TabRootView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: appState.isLoggedIn)
    }

}
