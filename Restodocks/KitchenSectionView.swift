import SwiftUI

struct KitchenSectionView: View {

    let titleKey: String
    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        List {

            NavigationLink {
                MenuView()
            } label: {
                Text(lang.t("menu"))
            }

            NavigationLink {
                TTKView()
            } label: {
                Text(lang.t("ttk"))
            }

            NavigationLink {
                ScheduleView()
            } label: {
                Text(lang.t("schedule"))
            }

        }
        .navigationTitle(lang.t(titleKey))
    }
}
