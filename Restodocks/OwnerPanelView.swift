import SwiftUI

struct OwnerPanelView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager

    var body: some View {
        List {
            Section(header: Text(lang.t("staff"))) {
                ForEach(accounts.employees) { employee in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(employee.fullName)
                            .font(.headline)

                        Text(employee.rolesArray.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(lang.t("owner_panel"))
        .task {
            await accounts.fetchEmployees()
        }
    }
}
