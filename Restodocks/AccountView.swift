import SwiftUI
import CoreData

struct AccountView: View {

    @EnvironmentObject var accounts: AccountManager
    @ObservedObject var lang = LocalizationManager.shared

    @FetchRequest(
        entity: EmployeeEntity.entity(),
        sortDescriptors: [],
        predicate: NSPredicate(format: "isActive == YES")
    )
    private var activeEmployees: FetchedResults<EmployeeEntity>

    var body: some View {

        VStack(spacing: 16) {

            if let employee = activeEmployees.first {
                Text(employee.fullName ?? "")
                    .font(.title2)
            }

            Button {
                accounts.logout()
            } label: {
                Text(lang.t("logout"))
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .padding()
        .navigationTitle(lang.t("account"))
    }
}
