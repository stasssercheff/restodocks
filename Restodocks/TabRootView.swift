import SwiftUI

struct TabRootView: View {

    @State private var selectedTab: Tab = .home

    enum Tab {
        case profile
        case custom
        case home
    }

    var body: some View {
        TabView(selection: $selectedTab) {

            // ===== ЛИЧНЫЙ КАБИНЕТ =====
            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Image(systemName: "person.crop.circle")
                Text("Профиль")
            }
            .tag(Tab.profile)

            // ===== КАСТОМНАЯ КНОПКА =====
            NavigationStack {
                CustomHomePlaceholderView()
            }
            .tabItem {
                Image(systemName: "star.fill")
                Text("Избранное")
            }
            .tag(Tab.custom)

            // ===== ГЛАВНАЯ =====
            NavigationStack {
                HomeContainerView()
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text("Главная")
            }
            .tag(Tab.home)
        }
    }
}