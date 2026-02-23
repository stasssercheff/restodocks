import SwiftUI

struct CreateOwnerView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var jobPosition: String = ""

    private let ownerJobPositions: [(String, String)] = [
        ("", "—"),
        ("executive_chef", "Шеф-повар"),
        ("manager", "Менеджер"),
        ("director", "Директор"),
        ("sous_chef", "Су-шеф")
    ]

    var body: some View {
        Form {

            Section(lang.t("owner")) {
                TextField(lang.t("name"), text: $fullName)

                TextField(lang.t("email"), text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)

                SecureField(lang.t("password"), text: $password)
            }

            Section(header: Text(lang.t("additional_position"))) {
                Picker(lang.t("position"), selection: $jobPosition) {
                    ForEach(ownerJobPositions, id: \.0) { p in
                        Text(p.1).tag(p.0)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                Button(lang.t("create_owner")) {
                    createOwner()
                }
                .disabled(fullName.isEmpty || email.isEmpty || password.isEmpty)
            }
        }
        .navigationTitle(lang.t("create_owner_title"))
    }

    private func createOwner() {
        accounts.createOwner(
            fullName: fullName,
            email: email,
            password: password
        )
        if let owner = accounts.currentEmployee {
            var roles = ["owner"]
            if !jobPosition.isEmpty {
                roles.append(jobPosition)
            }
            owner.rolesArray = roles
            accounts.saveContext()
        }
    }
}
