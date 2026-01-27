import SwiftUI

struct CreateOwnerView: View {

    let companyPin: String

    @EnvironmentObject var accounts: AccountManager
    @ObservedObject var lang = LocalizationManager.shared

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var pin = ""
    @State private var error = ""

    var body: some View {
        VStack(spacing: 18) {

            Text(lang.t("owner_setup"))
                .font(.largeTitle)
                .bold()

            Text(lang.t("create_owner"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("PIN компании: \(companyPin)")
                .font(.caption)
                .foregroundColor(.blue)
                .onAppear { pin = companyPin }

            TextField(lang.t("owner_name"), text: $name)
                .textFieldStyle(.roundedBorder)

            TextField(lang.t("owner_email"), text: $email)
                .keyboardType(.emailAddress)
                .textFieldStyle(.roundedBorder)

            SecureField(lang.t("password"), text: $password)
                .textFieldStyle(.roundedBorder)

            // PIN ВИДИМ
            TextField(lang.t("pin_code"), text: $pin)
                .textFieldStyle(.roundedBorder)

            if !error.isEmpty {
                Text(error).foregroundColor(.red)
            }

            Button(lang.t("create_owner")) {
                let ok = accounts.createOwner(
                    fullName: name,
                    email: email,
                    password: password,
                    pin: pin
                )

                if !ok {
                    error = lang.t("wrong_pin")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.isEmpty || email.isEmpty || password.isEmpty)

            Spacer()
        }
        .padding()
        .navigationBarBackButtonHidden(true)
    }
}
