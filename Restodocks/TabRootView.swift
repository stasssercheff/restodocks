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
                Text("Profile")
            }
            .tag(Tab.profile)

            // ===== КАСТОМ =====
            NavigationStack {
                CustomHomePlaceholderView()
            }
            .tabItem {
                Image(systemName: "star.fill")
                Text("Favorites")
            }
            .tag(Tab.custom)

            // ===== ГЛАВНАЯ =====
            NavigationStack {
                HomeView() // ✅ ВАЖНО: НЕ HomeContainerView
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text("Home")
            }
            .tag(Tab.home)
        }
    }
}
