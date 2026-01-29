import SwiftUI

struct HallView: View {
    @EnvironmentObject var lang: LocalizationManager

    var body: some View {
        List {
            // Products for dining room
            NavigationLink {
                ProductCatalogView(department: "dining_room")
            } label: {
                HStack {
                    Image(systemName: "cart")
                    Text(lang.t("products"))
                }
            }

            // Menu (for waitstaff) - view only
            NavigationLink {
                MenuView() // Dining room menu for waitstaff
            } label: {
                HStack {
                    Image(systemName: "book")
                    Text(lang.t("menu_waitstaff"))
                    Text("(\(lang.t("view_only")))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Schedule (by section) - view only
            NavigationLink {
                KitchenScheduleView() // Dining room schedule
                    .onAppear {
                        // Filter for hall department if needed
                    }
            } label: {
                HStack {
                    Image(systemName: "calendar")
                    Text(lang.t("schedule"))
                    Text("(\(lang.t("view_only")))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(lang.t("dining_room"))
    }
}
