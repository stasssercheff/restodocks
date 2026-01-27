import SwiftUI

struct OwnerPanelView: View {

    @EnvironmentObject var accounts: AccountManager
    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {

        VStack(spacing: 16) {

            Text(lang.t("management"))
                .font(.largeTitle)
                .bold()

            if let employees = accounts.establishment?.employees {

                ForEach(employees) { emp in
                    employeeRow(emp)
                }

            } else {
                Text(lang.t("no_employees"))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private func employeeRow(_ emp: EmployeeAccount) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(emp.fullName)
                    .font(.headline)

                Text(lang.t(emp.role.rawValue))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(lang.t(emp.department.rawValue))
                .font(.caption)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
