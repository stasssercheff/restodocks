import SwiftUI

struct HotKitchenView: View {
    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        List {
            NavigationLink {
                HotKitchenMenuView()
            } label: {
                Text(lang.t("menu"))
            }

            NavigationLink {
                HotKitchenTTKView()
            } label: {
                Text(lang.t("ttk"))
            }

            NavigationLink {
                HotKitchenScheduleView()
            } label: {
                Text(lang.t("schedule"))
            }
        }
        .navigationTitle(lang.t("hot_kitchen"))
    }
}