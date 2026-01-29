import SwiftUI

struct AppRoute: View {

    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var pro: ProAccess

    var body: some View {
        TabView {

            // 👤 ЛИЧНЫЙ КАБИНЕТ
            AppNavigationView {
                PersonalCabinetView()
            }
            .tabItem {
                Image(systemName: "person.crop.circle")
                Text(lang.t("cabinet"))
            }

            // ⭐ ЦЕНТРАЛЬНАЯ КНОПКА (ПОКА ЗАГЛУШКА)
            AppNavigationView {
                QuickActionView()
            }
            .tabItem {
                Image(systemName: "star.circle.fill")
                Text(lang.t("quick"))
            }

            // 🏠 ГЛАВНАЯ
            AppNavigationView {
                HomeView()
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text(lang.t("home"))
            }
        }
    }
}
