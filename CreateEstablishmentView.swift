import SwiftUI

struct CreateEstablishmentView: View {

    @EnvironmentObject var accounts: AccountManager
    @EnvironmentObject var lang: LocalizationManager

    @State private var name = ""
    @State private var email = ""

    var body: some View {

        AppNavigationView {

            VStack(spacing: 16) {

                Text(lang.t("create_company"))
                    .font(.largeTitle)
                    .bold()

                TextField(lang.t("company_name"), text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField(lang.t("owner_email"), text: $email)
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)

                Button(lang.t("create")) {
                    guard !name.isEmpty, !email.isEmpty else { return }
                    accounts.createEstablishment(
                        name: name,
                        ownerEmail: email
                    )
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle(lang.t("company_setup"))
        }
    }
}
