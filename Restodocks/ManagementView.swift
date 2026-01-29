import SwiftUI

struct ManagementView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager

    var body: some View {
        List {
            // Executive Chef
            NavigationLink {
                ExecutiveChefView()
            } label: {
                HStack {
                    Image(systemName: "chef.hat")
                    Text(lang.t("executive_chef"))
                }
            }

            // General Manager
            NavigationLink {
                GeneralManagerView()
            } label: {
                HStack {
                    Image(systemName: "person.badge.key")
                    Text(lang.t("general_manager"))
                }
            }
            }
            .navigationTitle(lang.t("management"))
    }
}
