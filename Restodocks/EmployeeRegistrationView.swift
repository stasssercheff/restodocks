import SwiftUI

struct EmployeeRegistrationView: View {

    @EnvironmentObject var accounts: AccountManager
    @ObservedObject var lang = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var email = ""
    @State private var pin = ""

    @State private var selectedRole: EmployeeRole = .chef
    @State private var selectedDepartment: Department = .kitchen
    @State private var birthDate = Date()

    var body: some View {

        VStack(spacing: 16) {

            Text(lang.t("employee_registration"))
                .font(.largeTitle)
                .bold()

            Text(lang.t("employee_registration"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField(lang.t("owner_name"), text: $fullName)
                .textFieldStyle(.roundedBorder)

            TextField(lang.t("email"), text: $email)
                .keyboardType(.emailAddress)
                .textFieldStyle(.roundedBorder)

            TextField(lang.t("pin_code"), text: $pin)
                .textFieldStyle(.roundedBorder)

            // 👔 Должность
            Picker(lang.t("role"), selection: $selectedRole) {
                ForEach(EmployeeRole.allCases) { role in
                    Text(lang.t(role.rawValue)).tag(role)
                }
            }
            .pickerStyle(.menu)

            // 🏢 Подразделение
            Picker(lang.t("department"), selection: $selectedDepartment) {
                ForEach(Department.allCases) { dep in
                    Text(lang.t(dep.rawValue)).tag(dep)
                }
            }
            .pickerStyle(.menu)

            // 🎂 Дата рождения
            DatePicker(
                lang.t("birth_date"),
                selection: $birthDate,
                displayedComponents: .date
            )

            // ✅ ПРАВИЛЬНО: Button + PrimaryButton
            Button {
                let success = accounts.registerEmployee(
                    fullName: fullName,
                    email: email,
                    role: selectedRole,
                    department: selectedDepartment,
                    birthDate: birthDate,
                    pin: pin
                )

                if success {
                    dismiss()
                }
            } label: {
                PrimaryButton(title: lang.t("continue"))
            }
            .disabled(fullName.isEmpty || email.isEmpty || pin.isEmpty)

            Spacer()
        }
        .padding()
        .navigationTitle(lang.t("employee_registration"))
    }
}
