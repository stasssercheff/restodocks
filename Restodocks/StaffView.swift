import SwiftUI

struct StaffView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager

    var body: some View {
        List {
            ForEach(accounts.employees) { employee in
                VStack(alignment: .leading, spacing: 4) {
                    Text(employee.fullName)
                        .font(.headline)

                    Text(employee.email)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(employee.department.capitalized)
                        .font(.caption)
                        .foregroundColor(.blue)

                    if !employee.rolesArray.isEmpty {
                        Text(employee.rolesArray.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(lang.t("staff"))
        .task {
            await accounts.fetchEmployees()
        }
        .refreshable {
            await accounts.fetchEmployees()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        popCurrentNavigationToRoot()
                    } label: {
                        Image(systemName: "house.fill")
                    }
                    .accessibilityLabel(lang.t("home"))
                    NavigationLink {
                        EmployeeRegistrationView()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}
