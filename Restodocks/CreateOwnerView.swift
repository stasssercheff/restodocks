import SwiftUI

struct CreateOwnerView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        Form {

            Section(lang.t("owner")) {
                TextField(lang.t("name"), text: $fullName)

                TextField(lang.t("email"), text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)

                SecureField(lang.t("password"), text: $password)
            }

            Section {
                Button(lang.t("create_owner")) {
                    accounts.createOwner(
                        fullName: fullName,
                        email: email,
                        password: password
                    )
                }
                .disabled(fullName.isEmpty || email.isEmpty || password.isEmpty)
            }
        }
        .navigationTitle(lang.t("create_owner_title"))
    }
}
