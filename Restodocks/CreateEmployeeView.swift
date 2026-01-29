//
//  CreateEmployeeView.swift
//  Restodocks
//

import SwiftUI

struct CreateEmployeeView: View {
    @EnvironmentObject var lang: LocalizationManager
    @EnvironmentObject var accounts: AccountManager
    @EnvironmentObject var appState: AppState

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var department = "kitchen"
    @State private var role = "cook"
    @State private var showSuccess = false

    let departments = [
        ("kitchen", "Кухня"),
        ("bar", "Бар"),
        ("dining_room", "Зал"),
        ("management", "Управление")
    ]

    let roles = [
        ("cook", "Повар"),
        ("bartender", "Бармен"),
        ("waiter", "Официант"),
        ("manager", "Менеджер")
    ]

    var body: some View {
        VStack {
            if showSuccess {
                // Экран успеха
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(AppTheme.success)

                    Text("Сотрудник зарегистрирован!")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)

                    Text("Теперь вы можете войти в систему")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    Spacer()

                    PrimaryButton(title: lang.t("login")) {
                        showSuccess = false
                        // Закрываем sheet, пользователь сможет войти
                    }
                    .padding(.horizontal)
                }
                .padding()
            } else {
                // Форма регистрации
                Form {
                    Section(lang.t("employee_profile")) {
                        TextField(lang.t("name"), text: $fullName)

                        TextField(lang.t("email"), text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)

                        SecureField(lang.t("password"), text: $password)
                    }

                    Section(lang.t("department")) {
                        Picker(lang.t("department"), selection: $department) {
                            ForEach(departments, id: \.0) { dept in
                                Text(dept.1).tag(dept.0)
                            }
                        }
                    }

                    Section(lang.t("position")) {
                        Picker(lang.t("position"), selection: $role) {
                            ForEach(roles, id: \.0) { r in
                                Text(r.1).tag(r.0)
                            }
                        }
                    }

                    Section {
                        PrimaryButton(title: lang.t("register_employee"),
                                    isDisabled: fullName.isEmpty || email.isEmpty || password.isEmpty) {
                            accounts.createEmployee(
                                fullName: fullName,
                                email: email,
                                password: password,
                                department: department,
                                role: role
                            )
                            showSuccess = true
                        }
                    }
                }
                .navigationTitle(lang.t("register_employee"))
            }
        }
    }
}