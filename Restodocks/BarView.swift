import SwiftUI

struct BarView: View {
    @EnvironmentObject var lang: LocalizationManager
    
    var body: some View {
        List {
            // Menu (by section) - view only
            NavigationLink {
                BarMenuView()
            } label: {
                HStack {
                    Image(systemName: "book")
                    Text(lang.t("menu"))
                    Text("(\(lang.t("view_only")))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Recipe Cards (by section) - view only
            NavigationLink {
                BarTTKView()
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                    Text(lang.t("recipe_cards"))
                    Text("(\(lang.t("view_only")))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Schedule (by section) - view only
            NavigationLink {
                KitchenScheduleView() // Bar schedule
                    .onAppear {
                        // Filter for bar department if needed
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
        .navigationTitle(lang.t("bar"))
    }
}
