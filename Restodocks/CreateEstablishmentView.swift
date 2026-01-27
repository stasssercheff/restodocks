import SwiftUI

struct CreateEstablishmentView: View {

    @EnvironmentObject var accounts: AccountManager
    @ObservedObject var lang = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""

    var body: some View {
        VStack(spacing: 20) {

            Text(lang.t("create_company"))
                .font(.largeTitle)
                .bold()

            TextField(lang.t("company_name"), text: $name)
                .textFieldStyle(.roundedBorder)

            TextField(lang.t("owner_email"), text: $email)
                .keyboardType(.emailAddress)
                .textFieldStyle(.roundedBorder)

            // ✅ ВОТ ТУТ ФИКС
            Button {
                accounts.createEstablishment(
                    name: name,
                    email: email
                )
                dismiss()
            } label: {
                PrimaryButton(title: lang.t("continue"))
            }
            .disabled(name.isEmpty || email.isEmpty)

            Spacer()
        }
        .padding()
        .navigationTitle(lang.t("company_setup"))
    }
}
