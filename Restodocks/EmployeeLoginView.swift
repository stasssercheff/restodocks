import SwiftUI

struct EmployeeLoginView: View {

    @EnvironmentObject var accounts: AccountManager
    @ObservedObject var lang = LocalizationManager.shared

    @State private var pin = ""
    @State private var error = ""

    var body: some View {
        VStack(spacing: 20) {

            Text(lang.t("employee_login"))
                .font(.largeTitle)
                .bold()

            TextField(lang.t("pin_code"), text: $pin)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)

            if !error.isEmpty {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button {
                let success = accounts.login(pin: pin)
                if !success {
                    error = lang.t("wrong_pin")
                }
            } label: {
                PrimaryButton(title: lang.t("login"))
            }
            .disabled(pin.isEmpty)

            Spacer()
        }
        .padding()
        .navigationTitle(lang.t("login"))
    }
}
