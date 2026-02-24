import SwiftUI

struct AccountView: View {
    @EnvironmentObject var accounts: AccountManager
    @ObservedObject var lang = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 16) {
            if let employee = accounts.currentEmployee {
                Text(employee.fullName)
                    .font(.title2)
            }

            Button {
                Task { @MainActor in
                    await accounts.logout()
                }
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
