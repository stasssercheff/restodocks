import SwiftUI

struct LoginView: View {

    @EnvironmentObject var accounts: AccountManager
    @ObservedObject var lang = LocalizationManager.shared

    @State private var email = ""
    @State private var password = ""
    @State private var error = false

    var body: some View {
        VStack(spacing: 20) {

            Text(lang.t("login"))
                .font(.largeTitle)
                .bold()

            TextField(lang.t("email"), text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .textFieldStyle(.roundedBorder)

            SecureField(lang.t("password"), text: $password)
                .textFieldStyle(.roundedBorder)

            Button {
                // ⚠️ ВРЕМЕННО:
                // используем password как pin,
                // чтобы НЕ ТРОГАТЬ AccountManager
                let success = accounts.login(pin: password)
                error = !success
            } label: {
                PrimaryButton(title: lang.t("login"))
            }
            .disabled(email.isEmpty || password.isEmpty)

            if error {
                Text(lang.t("wrong_login_or_password"))
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .padding()
        .navigationTitle(lang.t("login"))
    }
}
